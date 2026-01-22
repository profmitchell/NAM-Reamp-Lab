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
        modelName: String? = nil,
        chainName: String? = nil
    ) -> TrainingJob {
        let job = TrainingJob(
            inputFilePath: inputFilePath,
            outputFilePath: outputFilePath,
            modelName: modelName,
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
                // Clear first to ensure onChange fires even if set multiple times
                lastCompletedJob = nil
                
                // Use Task to ensure UI updates on next run loop
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(100))
                    lastCompletedJob = jobs[index]
                    print("✅ Set lastCompletedJob: \(jobs[index].chainName ?? "unknown") -> \(jobs[index].modelOutputPath ?? "no path")")
                }
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
        // Generate output model path - save directly to model folder with proper name
        let outputDir = AppSettings.shared.defaultModelFolder
        let sanitizedModelName = job.modelName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        
        // Create a training run folder for configs/checkpoints, but model goes directly to output folder
        let trainingRunDir = "\(outputDir)/.training_runs/\(sanitizedModelName)_\(UUID().uuidString.prefix(8))"
        let modelOutputPath = "\(outputDir)/\(sanitizedModelName).nam"
        
        // Create directories
        try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: trainingRunDir, withIntermediateDirectories: true)
        
        // Create config files for nam-full
        let configDir = "\(trainingRunDir)/configs"
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
        print("  Training run dir: \(trainingRunDir)")
        print("  Final model output: \(modelOutputPath)")
        
        // Write a batch training script that runs in a fresh shell
        let scriptPath = "\(trainingRunDir)/train.sh"
        let scriptContent = """
        #!/bin/zsh
        # Fresh environment for MPS GPU training
        export PATH="\(venvPath):/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin"
        export HOME="\(NSHomeDirectory())"
        
        cd "\(trainingRunDir)"
        "\(venvPath)/nam-full" --no-show \\
            "\(configDir)/data.json" \\
            "\(configDir)/model.json" \\
            "\(configDir)/learning.json" \\
            "\(trainingRunDir)"
        
        EXIT_CODE=$?
        if [ $EXIT_CODE -eq 0 ]; then
            echo ""
            echo "✅ Training complete!"
            MODEL_PATH=$(find "\(trainingRunDir)" -name "model.nam" -type f 2>/dev/null | head -1)
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
                    process.currentDirectoryURL = URL(fileURLWithPath: trainingRunDir)
                    
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
                        // Find the model in training run dir and copy to final destination
                        let fm = FileManager.default
                        var foundModelPath: String?
                        
                        if let contents = try? fm.contentsOfDirectory(atPath: trainingRunDir) {
                            let dateFolders = contents.filter { $0.contains("-") && !$0.contains(".") }.sorted().reversed()
                            for folder in dateFolders {
                                let tempModelPath = "\(trainingRunDir)/\(folder)/model.nam"
                                if fm.fileExists(atPath: tempModelPath) {
                                    foundModelPath = tempModelPath
                                    break
                                }
                            }
                        }
                        
                        // Also check directly in training run dir
                        if foundModelPath == nil {
                            let directPath = "\(trainingRunDir)/model.nam"
                            if fm.fileExists(atPath: directPath) {
                                foundModelPath = directPath
                            }
                        }
                        
                        if let sourcePath = foundModelPath {
                            // Copy/move to final destination with proper name
                            do {
                                // Remove existing if present
                                if fm.fileExists(atPath: modelOutputPath) {
                                    try fm.removeItem(atPath: modelOutputPath)
                                }
                                try fm.copyItem(atPath: sourcePath, toPath: modelOutputPath)
                                print("✅ Model saved to: \(modelOutputPath)")
                                continuation.resume(returning: modelOutputPath)
                            } catch {
                                print("⚠️ Failed to copy model: \(error). Using source path.")
                                continuation.resume(returning: sourcePath)
                            }
                        } else {
                            continuation.resume(returning: modelOutputPath)
                        }
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
