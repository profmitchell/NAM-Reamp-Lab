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
        let modelOutputPath = "\(outputDir)/\(modelName).nam"
        
        // Build Python training script
        let trainingScript = buildTrainingScript(
            inputPath: job.inputFilePath,
            outputPath: job.outputFilePath,
            modelOutputPath: modelOutputPath
        )
        
        // Run the training via Python
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: AppSettings.shared.pythonPath)
                    process.arguments = ["-c", trainingScript]
                    
                    // Set up environment
                    var env = ProcessInfo.processInfo.environment
                    let namPath = AppSettings.shared.namPackagePath
                    if !namPath.isEmpty {
                        env["PYTHONPATH"] = "\(namPath):\(env["PYTHONPATH"] ?? "")"
                    }
                    process.environment = env
                    
                    let outputPipe = Pipe()
                    let errorPipe = Pipe()
                    process.standardOutput = outputPipe
                    process.standardError = errorPipe
                    
                    currentProcess = process
                    
                    // Capture self for use in handlers
                    let trainer = self
                    
                    // Handle output for progress parsing
                    outputPipe.fileHandleForReading.readabilityHandler = { handle in
                        let data = handle.availableData
                        if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                            Task { @MainActor in
                                trainer.parseTrainingOutput(output, for: job)
                            }
                        }
                    }
                    
                    errorPipe.fileHandleForReading.readabilityHandler = { handle in
                        let data = handle.availableData
                        if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                            Task { @MainActor in
                                trainer.parseTrainingOutput(output, for: job)
                            }
                        }
                    }
                    
                    try process.run()
                    process.waitUntilExit()
                    
                    // Clean up handlers
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil
                    
                    if process.terminationStatus == 0 {
                        continuation.resume(returning: modelOutputPath)
                    } else {
                        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                        continuation.resume(throwing: TrainingError.trainingFailed(errorString))
                    }
                    
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func buildTrainingScript(inputPath: String, outputPath: String, modelOutputPath: String) -> String {
        let architecture = parameters.architecture.rawValue.lowercased()
        
        return """
        import sys
        import os
        
        # Add NAM to path if needed
        nam_path = '\(AppSettings.shared.namPackagePath)'
        if nam_path and nam_path not in sys.path:
            sys.path.insert(0, nam_path)
        
        from nam.train.core import train
        from nam.models.factory import get_model_config
        
        # Training configuration
        input_path = '\(inputPath)'
        output_path = '\(outputPath)'
        model_output_path = '\(modelOutputPath)'
        
        # Get model config for \(architecture)
        model_config = get_model_config('\(architecture)')
        
        # Training parameters
        training_config = {
            'epochs': \(parameters.epochs),
            'lr': \(parameters.learningRate),
            'batch_size': \(parameters.batchSize),
            'val_split': \(parameters.validationSplit),
        }
        
        # Run training
        print(f"Starting training: {input_path} -> {output_path}")
        print(f"Architecture: \(architecture)")
        print(f"Epochs: \(parameters.epochs)")
        
        try:
            train(
                input_path=input_path,
                output_path=output_path,
                model_config=model_config,
                **training_config
            )
            print(f"Training complete! Model saved to: {model_output_path}")
        except Exception as e:
            print(f"Training failed: {e}", file=sys.stderr)
            sys.exit(1)
        """
    }
    
    private func parseTrainingOutput(_ output: String, for job: TrainingJob) {
        outputBuffer += output
        
        guard let index = jobs.firstIndex(where: { $0.id == job.id }) else { return }
        
        jobs[index].logOutput += output
        
        // Parse epoch progress
        // Example: "Epoch 45/100"
        let epochPattern = #"Epoch\s+(\d+)/(\d+)"#
        if let regex = try? NSRegularExpression(pattern: epochPattern),
           let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)) {
            if let currentRange = Range(match.range(at: 1), in: output),
               let totalRange = Range(match.range(at: 2), in: output),
               let current = Int(output[currentRange]),
               let total = Int(output[totalRange]) {
                jobs[index].currentEpoch = current
                jobs[index].totalEpochs = total
                jobs[index].progress = Double(current) / Double(total)
            }
        }
        
        // Parse loss
        // Example: "loss: 0.0023" or "val_loss: 0.0019"
        let lossPattern = #"(?:val_)?loss:\s*([\d.]+)"#
        if let regex = try? NSRegularExpression(pattern: lossPattern),
           let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)) {
            if let lossRange = Range(match.range(at: 1), in: output),
               let loss = Double(output[lossRange]) {
                jobs[index].currentLoss = loss
            }
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
