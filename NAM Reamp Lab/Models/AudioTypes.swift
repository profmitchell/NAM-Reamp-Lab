//
//  AudioTypes.swift
//  NAM Reamp Lab
//

import Foundation
import AVFoundation

/// Audio device information
struct AudioDeviceInfo: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    let uid: String
    let isInput: Bool
    let isOutput: Bool
    let sampleRate: Double
    let channelCount: Int
    
    static func == (lhs: AudioDeviceInfo, rhs: AudioDeviceInfo) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Microphone permission status
enum MicrophonePermission {
    case granted
    case denied
    case notDetermined
}

/// Audio Engine Errors
enum AudioEngineError: LocalizedError {
    case engineNotInitialized
    case deviceConfigurationFailed
    case audioUnitLoadFailed
    case fileNotFound(String)
    case chainLoadFailed(String)
    case microphonePermissionDenied
    
    var errorDescription: String? {
        switch self {
        case .engineNotInitialized: return "Audio engine not initialized"
        case .deviceConfigurationFailed: return "Failed to configure audio device"
        case .audioUnitLoadFailed: return "Failed to load Audio Unit"
        case .fileNotFound(let path): return "File not found: \(path)"
        case .chainLoadFailed(let reason): return "Failed to load chain: \(reason)"
        case .microphonePermissionDenied: return "Microphone permission denied"
        }
    }
}
