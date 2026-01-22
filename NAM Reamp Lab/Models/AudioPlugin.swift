//
//  AudioPlugin.swift
//  NAM Reamp Lab
//
//  Created by Mitchell Cohen on 1/22/26.
//

import Foundation
import AVFoundation

/// Types of audio plugins supported by the app
enum PluginType: String, Codable, CaseIterable {
    case nam = "NAM Model"
    case audioUnit = "Audio Unit"
    case impulseResponse = "Impulse Response"
    
    var icon: String {
        switch self {
        case .nam: return "waveform.badge.mic"
        case .audioUnit: return "square.stack.3d.up"
        case .impulseResponse: return "waveform.path"
        }
    }
}

/// Represents an audio plugin in a processing chain
struct AudioPlugin: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var type: PluginType
    var path: String? // File path for NAM models and IRs
    var componentDescription: AudioComponentDescriptionCodable? // For Audio Units
    var presetData: Data? // Saved AU preset state
    var isEnabled: Bool
    var isBypassed: Bool
    
    init(
        id: UUID = UUID(),
        name: String,
        type: PluginType,
        path: String? = nil,
        componentDescription: AudioComponentDescriptionCodable? = nil,
        presetData: Data? = nil,
        isEnabled: Bool = true,
        isBypassed: Bool = false
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.path = path
        self.componentDescription = componentDescription
        self.presetData = presetData
        self.isEnabled = isEnabled
        self.isBypassed = isBypassed
    }
}

/// Codable wrapper for AudioComponentDescription
struct AudioComponentDescriptionCodable: Codable, Equatable {
    var componentType: UInt32
    var componentSubType: UInt32
    var componentManufacturer: UInt32
    var componentFlags: UInt32
    var componentFlagsMask: UInt32
    
    init(from description: AudioComponentDescription) {
        self.componentType = description.componentType
        self.componentSubType = description.componentSubType
        self.componentManufacturer = description.componentManufacturer
        self.componentFlags = description.componentFlags
        self.componentFlagsMask = description.componentFlagsMask
    }
    
    func toAudioComponentDescription() -> AudioComponentDescription {
        AudioComponentDescription(
            componentType: componentType,
            componentSubType: componentSubType,
            componentManufacturer: componentManufacturer,
            componentFlags: componentFlags,
            componentFlagsMask: componentFlagsMask
        )
    }
}

// MARK: - Sample Data for Previews

extension AudioPlugin {
    static let sampleNAM = AudioPlugin(
        name: "Clean Amp Model",
        type: .nam,
        path: "/path/to/model.nam"
    )
    
    static let sampleIR = AudioPlugin(
        name: "4x12 Cabinet IR",
        type: .impulseResponse,
        path: "/path/to/cabinet.wav"
    )
    
    static let sampleAU = AudioPlugin(
        name: "Reverb AU",
        type: .audioUnit
    )
}
