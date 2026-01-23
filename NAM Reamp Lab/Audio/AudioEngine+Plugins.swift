//
//  AudioEngine+Plugins.swift
//  NAM Reamp Lab
//

import Foundation
@preconcurrency import AVFoundation
import AppKit
import CoreAudioKit

extension AudioEngine {
    
    /// Loads a processing chain into the engine
    func loadChain(_ chain: ProcessingChain) async throws {
        // Stop engine temporarily
        let wasRunning = isRunning
        if wasRunning {
            stop()
        }
        
        // Clear existing effects
        clearEffects()
        
        currentChain = chain
        
        // Track loaded plugin indices for state restoration
        var loadedPluginIndex = 0
        
        // Load each plugin in the chain
        for plugin in chain.plugins where plugin.isEnabled && !plugin.isBypassed {
            switch plugin.type {
            case .nam:
                // Load NAM model into NAM Audio Unit
                if let namUnit = try await loadNAMAudioUnit() {
                    if let modelPath = plugin.path {
                        try await loadNAMModel(namUnit, modelPath: modelPath)
                    }
                    // Restore saved state if available (includes NAM model path)
                    if let presetData = plugin.presetData {
                        restorePluginState(at: loadedPluginIndex, from: presetData)
                    }
                    addEffectNode(namUnit)
                    loadedPluginIndex += 1
                }
                
            case .audioUnit:
                // Load the specified Audio Unit
                if let desc = plugin.componentDescription {
                    let unit = try await loadAudioUnit(desc.toAudioComponentDescription())
                    addEffectNode(unit)
                    // Restore saved preset state (includes all plugin settings)
                    if let presetData = plugin.presetData {
                        restorePluginState(at: loadedPluginIndex, from: presetData)
                        print("Restored AU preset for: \(plugin.name)")
                    }
                    loadedPluginIndex += 1
                }
                
            case .impulseResponse:
                // Load IR as convolution reverb
                if let irPath = plugin.path {
                    let irUnit = try await loadImpulseResponse(irPath)
                    addEffectNode(irUnit)
                    loadedPluginIndex += 1
                }
            }
        }
        
        // Rebuild the audio chain
        try rebuildAudioChain()
        
        // Restart if was running
        if wasRunning {
            try await start()
        }
        
        loadedAudioUnits = effectNodes
    }
    
    /// Updates the current chain with captured plugin states
    /// Call this before saving the chain to persist AU presets
    func updateChainWithPluginStates() -> ProcessingChain? {
        guard var chain = currentChain else { return nil }
        
        let states = capturePluginStates()
        
        // Map states back to plugins
        var pluginIndex = 0
        for i in 0..<chain.plugins.count {
            if chain.plugins[i].isEnabled && !chain.plugins[i].isBypassed {
                if let stateData = states[pluginIndex] {
                    chain.plugins[i].presetData = stateData
                    print("Saved state for plugin: \(chain.plugins[i].name)")
                }
                pluginIndex += 1
            }
        }
        
        currentChain = chain
        return chain
    }
    
    /// Clears all effects from the chain
    func clearEffects() {
        guard let engine = engine else { return }
        
        for node in effectNodes {
            engine.disconnectNodeOutput(node)
            engine.detach(node)
        }
        effectNodes.removeAll()
        loadedAudioUnits.removeAll()
        currentChain = nil
    }
    
    /// Captures the current state of all loaded Audio Units
    /// Returns a dictionary mapping plugin index to their preset data
    func capturePluginStates() -> [Int: Data] {
        var states: [Int: Data] = [:]
        
        for (index, unit) in effectNodes.enumerated() {
            if let fullState = unit.auAudioUnit.fullState {
                do {
                    let data = try NSKeyedArchiver.archivedData(withRootObject: fullState, requiringSecureCoding: false)
                    states[index] = data
                    print("Captured state for plugin \(index): \(unit.name) (\(data.count) bytes)")
                } catch {
                    print("Failed to capture state for plugin \(index): \(error)")
                }
            }
        }
        
        return states
    }
    
    /// Restores state to a loaded Audio Unit at the specified index
    func restorePluginState(at index: Int, from data: Data) {
        guard index < effectNodes.count else { return }
        let audioUnit = effectNodes[index]
        
        do {
            if let state = try NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSDictionary.self, NSString.self, NSNumber.self, NSData.self, NSArray.self], from: data) as? [String: Any] {
                audioUnit.auAudioUnit.fullState = state
            }
        } catch {
            print("Error restoring plugin state: \(error)")
        }
    }
    
    /// Gets the Audio Unit view for a loaded effect
    func getAudioUnitViewController(at index: Int) async -> NSViewController? {
        guard index < effectNodes.count else { return nil }
        let avAudioUnit = effectNodes[index]
        
        // Request the Audio Unit's custom view controller
        return await withCheckedContinuation { continuation in
            avAudioUnit.auAudioUnit.requestViewController { viewController in
                if let vc = viewController {
                    continuation.resume(returning: vc)
                } else {
                    // Fallback: Create a generic AU view
                    DispatchQueue.main.async {
                        let auView = AUGenericView(audioUnit: avAudioUnit.audioUnit)
                        auView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
                        let vc = NSViewController()
                        vc.view = auView
                        continuation.resume(returning: vc)
                    }
                }
            }
        }
    }
    
    // MARK: - NAM Specific
    
    /// Loads the NAM Audio Unit
    func loadNAMAudioUnit() async throws -> AVAudioUnit? {
        if let component = findNAMComponent() {
            do {
                print("Found NAM Component: \(component.name)")
                return try await loadAudioUnit(component.audioComponentDescription)
            } catch {
                print("Failed to load found NAM component: \(error)")
            }
        }
        
        let namDescription = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: FourCharCode("NAM "),
            componentManufacturer: FourCharCode("SdAk"),
            componentFlags: 0,
            componentFlagsMask: 0
        )
        
        return try await loadAudioUnit(namDescription)
    }
    
    /// Loads a NAM model file into the NAM Audio Unit
    func loadNAMModel(_ audioUnit: AVAudioUnit, modelPath: String) async throws {
        let auAudioUnit = audioUnit.auAudioUnit
        
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw AudioEngineError.fileNotFound(modelPath)
        }
        
        var state = auAudioUnit.fullState ?? [:]
        state["modelPath"] = modelPath
        state["NAMModelPath"] = modelPath
        state["model"] = modelPath
        auAudioUnit.fullState = state
        
        print("Loaded NAM model: \(URL(fileURLWithPath: modelPath).lastPathComponent)")
    }
    
    /// Finds the NAM Audio Unit component
    func findNAMComponent() -> AVAudioUnitComponent? {
        let manager = AVAudioUnitComponentManager.shared()
        let components = manager.components(matching: AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: 0,
            componentManufacturer: 0,
            componentFlags: 0,
            componentFlagsMask: 0
        ))
        
        let namComponent = components.first { component in
            let name = component.name.lowercased()
            let manufacturer = component.manufacturerName.lowercased()
            
            if name.contains("neural amp modeler") || name.contains("neuralampmodeler") || name == "nam" ||
                manufacturer.contains("steven atkinson") || manufacturer.contains("sdatkinson") {
                return true
            }
            return false
        }
        
        if let found = namComponent {
            print("Found NAM component: \(found.name) by \(found.manufacturerName)")
        }
        return namComponent
    }
    
    func rebuildAudioChain() throws {
        guard let engine = engine,
              let inputNode = inputNode,
              let mixer = mainMixerNode else {
            throw AudioEngineError.engineNotInitialized
        }
        
        removeLevelMetering()
        
        for effect in effectNodes {
            engine.disconnectNodeInput(effect)
            engine.disconnectNodeOutput(effect)
        }
        
        for bus in 0..<mixer.numberOfInputs {
            engine.disconnectNodeInput(mixer, bus: bus)
        }
        
        let inputNodeFormat = inputNode.outputFormat(forBus: 0)
        let processingFormat: AVAudioFormat
        if inputNodeFormat.sampleRate > 0 && inputNodeFormat.channelCount > 0 {
            processingFormat = inputNodeFormat
        } else {
            processingFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        }
        
        if effectNodes.isEmpty {
            engine.connect(inputNode, to: mixer, format: processingFormat)
        } else {
            var previousNode: AVAudioNode = inputNode
            for effectNode in effectNodes {
                engine.connect(previousNode, to: effectNode, format: processingFormat)
                previousNode = effectNode
            }
            engine.connect(previousNode, to: mixer, format: processingFormat)
        }
        
        configureMainMixerConnection()
        updateGains()
        installLevelMetering()
    }
    
    func loadAudioUnit(_ description: AudioComponentDescription) async throws -> AVAudioUnit {
        let isAppleAU = description.componentManufacturer == kAudioUnitManufacturer_Apple
        let options: AudioComponentInstantiationOptions = isAppleAU ? [] : .loadOutOfProcess
        
        return try await withCheckedThrowingContinuation { continuation in
            AVAudioUnit.instantiate(with: description, options: options) { audioUnit, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let audioUnit = audioUnit {
                    continuation.resume(returning: audioUnit)
                } else {
                    continuation.resume(throwing: AudioEngineError.audioUnitLoadFailed)
                }
            }
        }
    }
    
    func loadImpulseResponse(_ path: String) async throws -> AVAudioUnit {
        guard FileManager.default.fileExists(atPath: path) else {
            throw AudioEngineError.fileNotFound(path)
        }
        
        let irURL = URL(fileURLWithPath: path)
        let irFile = try AVAudioFile(forReading: irURL)
        let irFormat = irFile.processingFormat
        let irFrameCount = AVAudioFrameCount(irFile.length)
        
        guard let irBuffer = AVAudioPCMBuffer(pcmFormat: irFormat, frameCapacity: irFrameCount) else {
            throw AudioEngineError.chainLoadFailed("Failed to create IR buffer")
        }
        try irFile.read(into: irBuffer)
        
        let reverbDescription = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_Reverb2,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        
        let reverb = try await loadAudioUnit(reverbDescription)
        if let auReverb = reverb as? AVAudioUnitReverb {
            auReverb.wetDryMix = 100
        }
        
        return try createConvolutionNode(withIR: irBuffer)
    }
    
    func createConvolutionNode(withIR irBuffer: AVAudioPCMBuffer) throws -> AVAudioUnit {
        let matrixReverb = AVAudioUnitReverb()
        matrixReverb.wetDryMix = 100
        matrixReverb.loadFactoryPreset(.smallRoom)
        return matrixReverb
    }
    
    func addEffectNode(_ audioUnit: AVAudioUnit) {
        guard let engine = engine else { return }
        engine.attach(audioUnit)
        effectNodes.append(audioUnit)
    }
}
