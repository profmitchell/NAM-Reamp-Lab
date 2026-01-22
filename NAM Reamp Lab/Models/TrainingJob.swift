//
//  TrainingJob.swift
//  NAM Reamp Lab
//
//  Created by Mitchell Cohen on 1/22/26.
//

import Foundation

/// Status of a training job
enum TrainingStatus: String, Codable {
    case pending = "Pending"
    case running = "Running"
    case completed = "Completed"
    case failed = "Failed"
    case cancelled = "Cancelled"
    
    var icon: String {
        switch self {
        case .pending: return "clock"
        case .running: return "arrow.trianglehead.2.clockwise.rotate.90"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "minus.circle.fill"
        }
    }
    
    var color: String {
        switch self {
        case .pending: return "secondary"
        case .running: return "blue"
        case .completed: return "green"
        case .failed: return "red"
        case .cancelled: return "orange"
        }
    }
}

/// Represents a single NAM model training job
struct TrainingJob: Identifiable, Codable {
    let id: UUID
    var inputFilePath: String
    var outputFilePath: String
    var modelOutputPath: String?
    var chainName: String?
    var status: TrainingStatus
    var progress: Double // 0.0 to 1.0
    var currentEpoch: Int
    var totalEpochs: Int
    var currentLoss: Double?
    var startedAt: Date?
    var completedAt: Date?
    var errorMessage: String?
    var logOutput: String
    
    init(
        id: UUID = UUID(),
        inputFilePath: String,
        outputFilePath: String,
        modelOutputPath: String? = nil,
        chainName: String? = nil,
        status: TrainingStatus = .pending,
        progress: Double = 0.0,
        currentEpoch: Int = 0,
        totalEpochs: Int = 100,
        currentLoss: Double? = nil,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        errorMessage: String? = nil,
        logOutput: String = ""
    ) {
        self.id = id
        self.inputFilePath = inputFilePath
        self.outputFilePath = outputFilePath
        self.modelOutputPath = modelOutputPath
        self.chainName = chainName
        self.status = status
        self.progress = progress
        self.currentEpoch = currentEpoch
        self.totalEpochs = totalEpochs
        self.currentLoss = currentLoss
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.errorMessage = errorMessage
        self.logOutput = logOutput
    }
    
    /// Display name for the job
    var displayName: String {
        if let chainName = chainName {
            return chainName
        }
        return URL(fileURLWithPath: outputFilePath).deletingPathExtension().lastPathComponent
    }
    
    /// Duration of the training job
    var duration: TimeInterval? {
        guard let start = startedAt else { return nil }
        let end = completedAt ?? Date()
        return end.timeIntervalSince(start)
    }
    
    /// Formatted duration string
    var formattedDuration: String? {
        guard let duration = duration else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration)
    }
}

// MARK: - Training Parameters

/// Parameters for NAM model training
struct TrainingParameters: Codable {
    var architecture: ModelArchitecture
    var epochs: Int
    var learningRate: Double
    var batchSize: Int
    var validationSplit: Double
    var earlyStopping: Bool
    var patience: Int
    
    // Threshold ESR for early stopping (0.01 = 1% error, excellent quality)
    var thresholdESR: Double?
    
    init(
        architecture: ModelArchitecture = .wavenet,
        epochs: Int = 50,  // Reduced from 100 - early stopping will kick in if quality is good
        learningRate: Double = 0.004,
        batchSize: Int = 16,
        validationSplit: Double = 0.1,
        earlyStopping: Bool = true,
        patience: Int = 20,
        thresholdESR: Double? = 0.02  // Stop early if ESR < 2%
    ) {
        self.architecture = architecture
        self.epochs = epochs
        self.learningRate = learningRate
        self.batchSize = batchSize
        self.validationSplit = validationSplit
        self.earlyStopping = earlyStopping
        self.patience = patience
        self.thresholdESR = thresholdESR
    }
    
    static let `default` = TrainingParameters()
    
    static let quick = TrainingParameters(
        epochs: 25,
        patience: 10,
        thresholdESR: 0.05  // 5% - good enough for quick test
    )
    
    static let full = TrainingParameters(
        epochs: 250,
        patience: 50,
        thresholdESR: 0.01  // 1% - highest quality
    )
}

/// NAM model architecture types
enum ModelArchitecture: String, Codable, CaseIterable {
    case wavenet = "WaveNet"
    case lstm = "LSTM"
    case convnet = "ConvNet"
    
    var description: String {
        switch self {
        case .wavenet: return "WaveNet - Best quality, moderate speed"
        case .lstm: return "LSTM - Good quality, faster"
        case .convnet: return "ConvNet - Fast training, good for simpler tones"
        }
    }
}

// MARK: - Sample Data for Previews

extension TrainingJob {
    static let samplePending = TrainingJob(
        inputFilePath: "/audio/input.wav",
        outputFilePath: "/audio/clean_amp.wav",
        chainName: "Clean Amp",
        status: .pending
    )
    
    static let sampleRunning = TrainingJob(
        inputFilePath: "/audio/input.wav",
        outputFilePath: "/audio/heavy_rhythm.wav",
        chainName: "Heavy Rhythm",
        status: .running,
        progress: 0.45,
        currentEpoch: 45,
        totalEpochs: 100,
        currentLoss: 0.0023,
        startedAt: Date().addingTimeInterval(-300)
    )
    
    static let sampleCompleted = TrainingJob(
        inputFilePath: "/audio/input.wav",
        outputFilePath: "/audio/jazz_clean.wav",
        modelOutputPath: "/models/jazz_clean.nam",
        chainName: "Jazz Clean",
        status: .completed,
        progress: 1.0,
        currentEpoch: 100,
        totalEpochs: 100,
        startedAt: Date().addingTimeInterval(-600),
        completedAt: Date()
    )
    
    static let sampleFailed = TrainingJob(
        inputFilePath: "/audio/input.wav",
        outputFilePath: "/audio/broken.wav",
        chainName: "Broken Chain",
        status: .failed,
        errorMessage: "CUDA out of memory"
    )
    
    static let sampleList: [TrainingJob] = [
        sampleRunning,
        samplePending,
        sampleCompleted,
        sampleFailed
    ]
}
