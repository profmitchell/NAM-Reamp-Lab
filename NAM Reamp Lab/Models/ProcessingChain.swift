//
//  ProcessingChain.swift
//  NAM Reamp Lab
//
//  Created by Mitchell Cohen on 1/22/26.
//

import Foundation
import SwiftUI

/// Represents a complete audio processing chain with multiple plugins
struct ProcessingChain: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var isEnabled: Bool
    var plugins: [AudioPlugin]
    var createdAt: Date
    var modifiedAt: Date
    
    init(
        id: UUID = UUID(),
        name: String = "New Chain",
        isEnabled: Bool = true,
        plugins: [AudioPlugin] = [],
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.plugins = plugins
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
    
    /// Returns the output filename for this chain based on its name
    var outputFileName: String {
        let sanitized = name
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
        return "\(sanitized).wav"
    }
    
    /// Adds a plugin to the chain
    mutating func addPlugin(_ plugin: AudioPlugin) {
        plugins.append(plugin)
        modifiedAt = Date()
    }
    
    /// Removes a plugin at the specified index
    mutating func removePlugin(at index: Int) {
        guard plugins.indices.contains(index) else { return }
        plugins.remove(at: index)
        modifiedAt = Date()
    }
    
    /// Moves plugins within the chain
    mutating func movePlugins(from source: IndexSet, to destination: Int) {
        plugins.move(fromOffsets: source, toOffset: destination)
        modifiedAt = Date()
    }
    
    /// Toggles the enabled state of a plugin
    mutating func togglePlugin(at index: Int) {
        guard plugins.indices.contains(index) else { return }
        plugins[index].isEnabled.toggle()
        modifiedAt = Date()
    }
    
    /// Toggles the bypass state of a plugin
    mutating func toggleBypass(at index: Int) {
        guard plugins.indices.contains(index) else { return }
        plugins[index].isBypassed.toggle()
        modifiedAt = Date()
    }
}

// MARK: - Sample Data for Previews

extension ProcessingChain {
    static let sample = ProcessingChain(
        name: "Clean Boost AmpA",
        plugins: [
            AudioPlugin(name: "Tube Screamer", type: .audioUnit),
            AudioPlugin(name: "Fender Twin Model", type: .nam, path: "/models/fender_twin.nam"),
            AudioPlugin(name: "Vintage 2x12 IR", type: .impulseResponse, path: "/irs/vintage_2x12.wav")
        ]
    )
    
    static let sampleList: [ProcessingChain] = [
        ProcessingChain(
            name: "Clean Boost AmpA",
            plugins: [
                AudioPlugin(name: "Tube Screamer", type: .audioUnit),
                AudioPlugin(name: "Fender Twin", type: .nam, path: "/models/fender.nam")
            ]
        ),
        ProcessingChain(
            name: "Heavy Rhythm",
            isEnabled: true,
            plugins: [
                AudioPlugin(name: "5150 High Gain", type: .nam, path: "/models/5150.nam"),
                AudioPlugin(name: "Mesa 4x12", type: .impulseResponse, path: "/irs/mesa.wav")
            ]
        ),
        ProcessingChain(
            name: "Jazz Clean",
            isEnabled: false,
            plugins: [
                AudioPlugin(name: "Roland JC-120", type: .nam, path: "/models/jc120.nam")
            ]
        )
    ]
}
