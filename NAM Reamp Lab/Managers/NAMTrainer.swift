//
//  NAMTrainer.swift
//  NAM Reamp Lab
//
//  Created by Mitchell Cohen on 1/22/26.
//

import Foundation
import Combine

/// Manages NAM model training via Python
@MainActor
class NAMTrainer: ObservableObject {
    static let shared = NAMTrainer()
    
    // MARK: - Published Properties
    
    @Published var jobs: [TrainingJob] = []
    @Published var currentJob: TrainingJob?
    @Published private(set) var isTraining: Bool = false
    @Published private(set) var overallProgress: Double = 0.0
    @Published var parameters: TrainingParameters = .default
    
    // Queue management
    @Published var queuedJobIds: [UUID] = []
    
    /// Last completed job - used to show completion dialog
    @Published var lastCompletedJob: TrainingJob?
    
    // MARK: - Private Properties
    
    private let pythonManager = PythonManager.shared
    private var currentProcess: Process?
    private var cancellables = Set<AnyCancellable>()
    private var outputBuffer: String = ""
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Job Management
    
    /// Creates a training job
    @discardableResult
    func createJob(
        inputFilePath: String,
        outputFilePath: String,
        chainName: String? = nil
    ) -> TrainingJob {
        let job = TrainingJob(
            inputFilePath: inputFilePath,
            outputFilePath: outputFilePath,
            chainName: chainName,
            totalEpochs: parameters.epochs
        )
        jobs.append(job)
        return job
    }
    
    /// Creates multiple jobs from output files
    func createJobsFromOutputFiles(_ outputFiles: [URL], inputFile: URL) -> [TrainingJob] {
        return outputFiles.map { outputURL in
            let chainName = outputURL.deletingPathExtension().lastPathComponent
            return createJob(
                inputFilePath: inputFile.path,
                outputFilePath: outputURL.path,
                chainName: chainName
            )
        }
    }
    
    /// Removes a job
    func removeJob(_ job: TrainingJob) {
        jobs.removeAll { $0.id == job.id }
        queuedJobIds.removeAll { $0 == job.id }
    }
    
    /// Clears completed jobs
    func clearCompletedJobs() {
        jobs.removeAll { $0.status == .completed || $0.status == .failed || $0.status == .cancelled }
    }
    
    /// Clears all jobs
    func clearAllJobs() {
        guard !isTraining else { return }
        jobs.removeAll()
        queuedJobIds.removeAll()
    }
    
    // MARK: - Training
    
    /// Trains a single model
    func trainSingle(_ job: TrainingJob) async throws {
        guard pythonManager.status.isReady else {
            throw TrainingError.pythonNotReady
        }
        
        guard let jobIndex = jobs.firstIndex(where: { $0.id == job.id }) else {
            throw TrainingError.jobNotFound
        }
        
        isTraining = true
        currentJob = job
        jobs[jobIndex].status = .running
        jobs[jobIndex].startedAt = Date()
        outputBuffer = ""
        
        defer {
            isTraining = false
            currentJob = nil
        }
        
        do {
            let modelOutputPath = try await runTraining(for: jobs[jobIndex])
            
            // Update job on success
            if let index = jobs.firstIndex(where: { $0.id == job.id }) {
                jobs[index].status = .completed
                jobs[index].progress = 1.0
                jobs[index].completedAt = Date()
                jobs[index].modelOutputPath = modelOutputPath
                
                // Set lastCompletedJob to trigger completion dialog
                lastCompletedJob = jobs[index]
            }
        } catch {
            // Update job on failure
            if let index = jobs.firstIndex(where: { $0.id == job.id }) {
                jobs[index].status = .failed
                jobs[index].errorMessage = error.localizedDescription
                jobs[index].completedAt = Date()
            }
            throw error
        }
    }
    
    /// Trains all pending jobs in the queue
    func trainAllPending() async throws {
        let pendingJobs = jobs.filter { $0.status == .pending }
        guard !pendingJobs.isEmpty else { return }
        
        let totalJobs = pendingJobs.count
        var completedCount = 0
        
        for job in pendingJobs {
            do {
                try await trainSingle(job)
                completedCount += 1
                overallProgress = Double(completedCount) / Double(totalJobs)
            } catch {
                // Continue with next job even if one fails
                completedCount += 1
                overallProgress = Double(completedCount) / Double(totalJobs)
            }
        }
        
        overallProgress = 0.0
    }
    
    /// Cancels the current training
    func cancelCurrentTraining() {
        currentProcess?.terminate()
        currentProcess = nil
        
        if let job = currentJob, let index = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[index].status = .cancelled
            jobs[index].completedAt = Date()
        }
        
        isTraining = false
        currentJob = nil
    }
    
    // MARK: - Private Methods
    
    private func runTraining(for job: TrainingJob) async throws -> String {
        // Generate output model path
        let outputDir = AppSettings.shared.defaultModelFolder
        let modelName = URL(fileURLWithPath: job.outputFilePath).deletingPathExtension().lastPathComponent
        let trainingOutputDir = "\(outputDir)/\(modelName)_training"
        let modelOutputPath = "\(trainingOutputDir)/model.nam"
        
        // Create training output directory
        try FileManager.default.createDirectory(atPath: trainingOutputDir, withIntermediateDirectories: true)
        
        // Create config files for nam-full
        let configDir = "\(trainingOutputDir)/configs"
        try FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        
        // Data config
        let dataConfig = """
        {
            "train": {
                "start_seconds": null,
                "stop_seconds": -9.0,
                "ny": 8192
            },
            "validation": {
                "start_seconds": -9.0,
                "stop_seconds": null,
                "ny": null
            },
            "common": {
                "x_path": "\(job.inputFilePath)",
                "y_path": "\(job.outputFilePath)",
                "delay": 0
            }
        }
        """
        try dataConfig.write(toFile: "\(configDir)/data.json", atomically: true, encoding: .utf8)
        
        // Model config (WaveNet standard)
        let modelConfig = """
        {
            "net": {
                "name": "WaveNet",
                "config": {
                    "layers_configs": [
                        {
                            "condition_size": 1,
                            "input_size": 1,
                            "channels": 16,
                            "head_size": 8,
                            "kernel_size": 3,
                            "dilations": [1, 2, 4, 8, 16, 32, 64, 128, 256, 512],
                            "activation": "Tanh",
                            "gated": false,
                            "head_bias": false
                        },
                        {
                            "condition_size": 1,
                            "input_size": 16,
                            "channels": 8,
                            "head_size": 1,
                            "kernel_size": 3,
                            "dilations": [1, 2, 4, 8, 16, 32, 64, 128, 256, 512],
                            "activation": "Tanh",
                            "gated": false,
                            "head_bias": true
                        }
                    ],
                    "head_scale": 0.02
                }
            },
            "optimizer": {
                "lr": \(parameters.learningRate)
            },
            "lr_scheduler": {
                "class": "ExponentialLR",
                "kwargs": {
                    "gamma": 0.993
                }
            }
        }
        """
        try modelConfig.write(toFile: "\(configDir)/model.json", atomically: true, encoding: .utf8)
        
        // Learning config - Use MPS (Apple GPU) for fast training
        let learningConfig = """
        {
            "train_dataloader": {
                "batch_size": \(parameters.batchSize),
                "shuffle": true,
                "pin_memory": false,
                "drop_last": true,
                "num_workers": 0
            },
            "val_dataloader": {},
            "trainer": {
                "accelerator": "mps",
                "devices": 1,
                "max_epochs": \(parameters.epochs)
            },
            "trainer_fit_kwargs": {}
        }
        """
        try learningConfig.write(toFile: "\(configDir)/learning.json", atomically: true, encoding: .utf8)
        
        // Use nam-full CLI - spawn as completely detached process
        let venvPath = "/Users/Shared/CohenConcepts/NAM Reamp Lab/.venv/bin"
        
        print("Training using nam-full CLI")
        print("  Data config: \(configDir)/data.json")
        print("  Model config: \(configDir)/model.json")
        print("  Learning config: \(configDir)/learning.json")
        print("  Output dir: \(trainingOutputDir)")
        
        // Write a batch training script that runs in a fresh shell
        let scriptPath = "\(trainingOutputDir)/train.sh"
        let scriptContent = """
        #!/bin/zsh
        # Fresh environment for MPS GPU training
        export PATH="\(venvPath):/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin"
        export HOME="\(NSHomeDirectory())"
        
        cd "\(trainingOutputDir)"
        "\(venvPath)/nam-full" --no-show \\
            "\(configDir)/data.json" \\
            "\(configDir)/model.json" \\
            "\(configDir)/learning.json" \\
            "\(trainingOutputDir)"
        
        EXIT_CODE=$?
        if [ $EXIT_CODE -eq 0 ]; then
            echo ""
            echo "✅ Training complete!"
            MODEL_PATH=$(find "\(trainingOutputDir)" -name "model.nam" -type f 2>/dev/null | head -1)
            echo "Model saved to: $MODEL_PATH"
        else
            echo ""
            echo "❌ Training failed with exit code $EXIT_CODE"
        fi
        exit $EXIT_CODE
        """
        try scriptContent.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        
        // Make executable
        let chmod = Process()
        chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmod.arguments = ["+x", scriptPath]
        try chmod.run()
        chmod.waitUntilExit()
        
        // Run via /usr/bin/env with completely clean environment
        // This is critical - don't inherit ANY environment from the Swift app
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                    process.arguments = ["-i", "/bin/zsh", scriptPath]  // -i = ignore inherited environment
                    process.currentDirectoryURL = URL(fileURLWithPath: trainingOutputDir)
                    
                    // Minimal clean environment - don't inherit from app
                    process.environment = [
                        "PATH": "\(venvPath):/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin",
                        "HOME": NSHomeDirectory(),
                        "TERM": "xterm-256color",
                        "LANG": "en_US.UTF-8"
                    ]
                    
                    let outputPipe = Pipe()
                    let errorPipe = Pipe()
                    process.standardOutput = outputPipe
                    process.standardError = errorPipe
                    
                    let trainer = self
                    let jobCopy = job
                    
                    // Async read handlers - only print errors, not progress spam
                    outputPipe.fileHandleForReading.readabilityHandler = { handle in
                        let data = handle.availableData
                        guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }
                        // Only parse, don't echo to console
                        DispatchQueue.main.async {
                            trainer.parseTrainingOutput(output, for: jobCopy)
                        }
                    }
                    
                    errorPipe.fileHandleForReading.readabilityHandler = { handle in
                        let data = handle.availableData
                        guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }
                        // Only print actual errors, not warnings
                        if output.contains("Error") || output.contains("error:") || output.contains("failed") {
                            print("❌ \(output)")
                        }
                        DispatchQueue.main.async {
                            trainer.parseTrainingOutput(output, for: jobCopy)
                        }
                    }
                    
                    DispatchQueue.main.async {
                        self.currentProcess = process
                    }
                    
                    try process.run()
                    process.waitUntilExit()
                    
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil
                    
                    if process.terminationStatus == 0 {
                        // Find the model
                        let fm = FileManager.default
                        if let contents = try? fm.contentsOfDirectory(atPath: trainingOutputDir) {
                            let dateFolders = contents.filter { $0.contains("-") && !$0.contains(".") }.sorted().reversed()
                            for folder in dateFolders {
                                let modelPath = "\(trainingOutputDir)/\(folder)/model.nam"
                                if fm.fileExists(atPath: modelPath) {
                                    continuation.resume(returning: modelPath)
                                    return
                                }
                            }
                        }
                        continuation.resume(returning: "\(trainingOutputDir)/model.nam")
                    } else {
                        continuation.resume(throwing: TrainingError.trainingFailed("Exit code: \(process.terminationStatus)"))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // Throttle log updates to reduce UI spam
    private var lastLogUpdate = Date.distantPast
    private let logUpdateInterval: TimeInterval = 2.0  // Update UI at most every 2 seconds
    
    private func parseTrainingOutput(_ output: String, for job: TrainingJob) {
        guard let index = jobs.firstIndex(where: { $0.id == job.id }) else { return }
        
        // Always accumulate raw output (for debugging if needed)
        outputBuffer += output
        
        // Parse epoch progress - always update progress bar
        let epochPattern = #"Epoch\s+(\d+)"#
        if let regex = try? NSRegularExpression(pattern: epochPattern),
           let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)) {
            if let currentRange = Range(match.range(at: 1), in: output),
               let current = Int(output[currentRange]) {
                jobs[index].currentEpoch = current
                jobs[index].progress = Double(current) / Double(jobs[index].totalEpochs)
            }
        }
        
        // Parse ESR (Error-to-Signal Ratio) - key quality metric
        let esrPattern = #"ESR[=:\s]*([\d.]+)"#
        if let regex = try? NSRegularExpression(pattern: esrPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)) {
            if let esrRange = Range(match.range(at: 1), in: output),
               let esr = Double(output[esrRange]) {
                jobs[index].currentLoss = esr
            }
        }
        
        // Minimal UI log - only show status, not spam
        let now = Date()
        if now.timeIntervalSince(lastLogUpdate) >= logUpdateInterval {
            lastLogUpdate = now
            let epoch = jobs[index].currentEpoch
            let total = jobs[index].totalEpochs
            let esr = jobs[index].currentLoss.map { String(format: "%.4f", $0) } ?? "..."
            jobs[index].logOutput = "Training: Epoch \(epoch)/\(total) • ESR: \(esr)"
        }
    }
}

// MARK: - Errors

enum TrainingError: LocalizedError {
    case pythonNotReady
    case jobNotFound
    case trainingFailed(String)
    case cancelled
    
    var errorDescription: String? {
        switch self {
        case .pythonNotReady:
            return "Python environment is not ready"
        case .jobNotFound:
            return "Training job not found"
        case .trainingFailed(let message):
            return "Training failed: \(message)"
        case .cancelled:
            return "Training was cancelled"
        }
    }
}
