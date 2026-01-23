//
//  AudioUnitHostManager.swift
//  NAM Reamp Lab
//
//  Created by Mitchell Cohen on 1/22/26.
//

import Foundation
import AVFoundation
import AudioToolbox
import Combine
import Accelerate  // For vDSP convolution

/// Information about an available Audio Unit
struct AudioUnitInfo: Identifiable, Hashable {
    let id: UUID = UUID()
    let name: String
    let manufacturer: String
    let componentDescription: AudioComponentDescription
    let type: AudioUnitType
    let version: UInt32
    let icon: String
    
    var displayName: String {
        "\(name) (\(manufacturer))"
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(componentDescription.componentType)
        hasher.combine(componentDescription.componentSubType)
        hasher.combine(componentDescription.componentManufacturer)
    }
    
    static func == (lhs: AudioUnitInfo, rhs: AudioUnitInfo) -> Bool {
        lhs.componentDescription.componentType == rhs.componentDescription.componentType &&
        lhs.componentDescription.componentSubType == rhs.componentDescription.componentSubType &&
        lhs.componentDescription.componentManufacturer == rhs.componentDescription.componentManufacturer
    }
}

/// Audio Unit types we care about
enum AudioUnitType: String, CaseIterable {
    case effect = "Effect"
    case musicEffect = "Music Effect"
    case generator = "Generator"
    case instrument = "Instrument"
    case mixer = "Mixer"
    case unknown = "Unknown"
    
    static func from(_ componentType: UInt32) -> AudioUnitType {
        switch componentType {
        case kAudioUnitType_Effect:
            return .effect
        case kAudioUnitType_MusicEffect:
            return .musicEffect
        case kAudioUnitType_Generator:
            return .generator
        case kAudioUnitType_MusicDevice:
            return .instrument
        case kAudioUnitType_Mixer:
            return .mixer
        default:
            return .unknown
        }
    }
}

/// Manages Audio Unit discovery and hosting using AVFoundation
@MainActor
class AudioUnitHostManager: ObservableObject {
    static let shared = AudioUnitHostManager()
    
    // MARK: - Published Properties
    
    @Published private(set) var availableAudioUnits: [AudioUnitInfo] = []
    @Published private(set) var isScanning: Bool = false
    @Published private(set) var lastScanDate: Date?
    @Published var selectedAudioUnit: AudioUnitInfo?
    
    // Audio engine for processing
    @Published private(set) var isEngineRunning: Bool = false
    
    // MARK: - Private Properties
    
    private var audioEngine: AVAudioEngine?
    private var loadedAudioUnits: [UUID: AVAudioUnit] = [:]
    private let componentManager = AVAudioUnitComponentManager.shared()
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    private init() {
        setupNotifications()
    }
    
    // MARK: - Public Methods
    
    /// Scans for available Audio Units
    func scanForAudioUnits() async {
        guard !isScanning else { return }
        isScanning = true
        
        defer {
            isScanning = false
            lastScanDate = Date()
        }
        
        var units: [AudioUnitInfo] = []
        
        // Scan for effect Audio Units
        let effectTypes: [UInt32] = [
            kAudioUnitType_Effect,
            kAudioUnitType_MusicEffect
        ]
        
        for type in effectTypes {
            let description = AudioComponentDescription(
                componentType: type,
                componentSubType: 0,
                componentManufacturer: 0,
                componentFlags: 0,
                componentFlagsMask: 0
            )
            
            let components = componentManager.components(matching: description)
            
            for component in components {
                let info = AudioUnitInfo(
                    name: component.name,
                    manufacturer: component.manufacturerName,
                    componentDescription: component.audioComponentDescription,
                    type: AudioUnitType.from(component.audioComponentDescription.componentType),
                    version: UInt32(component.version),
                    icon: component.hasCustomView ? "rectangle.and.pencil.and.ellipsis" : "square.stack.3d.up"
                )
                units.append(info)
            }
        }
        
        // Sort by manufacturer, then name
        units.sort { 
            if $0.manufacturer != $1.manufacturer {
                return $0.manufacturer < $1.manufacturer
            }
            return $0.name < $1.name
        }
        
        availableAudioUnits = units
    }
    
    /// Finds NAM Audio Unit if installed
    /// The NAM plugin is typically named "Neural Amp Modeler" by Steven Atkinson
    func findNAMAudioUnit() -> AudioUnitInfo? {
        return availableAudioUnits.first { info in
            // Check for exact NAM plugin - be specific to avoid false positives
            let name = info.name.lowercased()
            let manufacturer = info.manufacturer.lowercased()
            
            // NAM by Steven Atkinson
            if name.contains("neural amp modeler") { return true }
            
            // Exact match for "NAM" as a word (not substring like "dyNAMics")
            if name == "nam" || name.hasPrefix("nam ") || name.hasSuffix(" nam") || name.contains(" nam ") { return true }
            
            // Check manufacturer
            if manufacturer.contains("steven atkinson") || manufacturer.contains("sdatkinson") { return true }
            
            return false
        }
    }
    
    /// Loads an Audio Unit asynchronously
    func loadAudioUnit(_ info: AudioUnitInfo) async throws -> AVAudioUnit {
        // Check if already loaded
        if let existing = loadedAudioUnits.values.first(where: { 
            $0.audioComponentDescription.componentType == info.componentDescription.componentType &&
            $0.audioComponentDescription.componentSubType == info.componentDescription.componentSubType &&
            $0.audioComponentDescription.componentManufacturer == info.componentDescription.componentManufacturer
        }) {
            return existing
        }
        
        // Instantiate the Audio Unit
        // Use .loadOutOfProcess for third-party plugins to avoid code signature issues
        let isAppleAU = info.componentDescription.componentManufacturer == kAudioUnitManufacturer_Apple
        let options: AudioComponentInstantiationOptions = isAppleAU ? [] : .loadOutOfProcess
        
        return try await withCheckedThrowingContinuation { continuation in
            AVAudioUnit.instantiate(with: info.componentDescription, options: options) { audioUnit, error in
                if let error = error {
                    print("Failed to load AU '\(info.name)' (out-of-process: \(!isAppleAU)): \(error.localizedDescription)")
                    continuation.resume(throwing: AudioUnitError.loadFailed(info.name, error.localizedDescription))
                    return
                }
                
                guard let audioUnit = audioUnit else {
                    continuation.resume(throwing: AudioUnitError.loadFailed(info.name, "Unknown error"))
                    return
                }
                
                print("Successfully loaded AU: \(info.name)")
                Task { @MainActor in
                    self.loadedAudioUnits[info.id] = audioUnit
                }
                continuation.resume(returning: audioUnit)
            }
        }
    }
    
    /// Unloads an Audio Unit
    func unloadAudioUnit(_ id: UUID) {
        loadedAudioUnits.removeValue(forKey: id)
    }
    
    /// Unloads all Audio Units
    func unloadAllAudioUnits() {
        loadedAudioUnits.removeAll()
    }
    
    // MARK: - Audio Engine
    
    /// Initializes the audio engine
    func initializeEngine() throws {
        audioEngine = AVAudioEngine()
    }
    
    /// Starts the audio engine for real-time preview
    func startEngine() throws {
        guard let engine = audioEngine else {
            throw AudioUnitError.engineNotInitialized
        }
        
        try engine.start()
        isEngineRunning = true
    }
    
    /// Stops the audio engine
    func stopEngine() {
        audioEngine?.stop()
        isEngineRunning = false
    }
    
    /// Processes an audio file through a chain of plugins
    func processAudioFile(
        inputURL: URL,
        outputURL: URL,
        plugins: [AudioPlugin],
        progressHandler: @escaping (Double) -> Void
    ) async throws {
        print("🔧 AudioUnitHostManager: Processing audio file")
        print("   Input: \(inputURL.lastPathComponent)")
        print("   Output: \(outputURL.lastPathComponent)")
        
        // Load the input audio file
        let inputFile = try AVAudioFile(forReading: inputURL)
        let format = inputFile.processingFormat
        let frameCount = AVAudioFrameCount(inputFile.length)
        print("   Format: \(format.sampleRate)Hz, \(format.channelCount) channels, \(frameCount) frames")
        
        // Create input buffer
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw AudioUnitError.bufferCreationFailed
        }
        try inputFile.read(into: inputBuffer)
        print("   Loaded \(inputBuffer.frameLength) frames into buffer")
        
        // Create output file
        let outputFile = try AVAudioFile(forWriting: outputURL, settings: inputFile.fileFormat.settings)
        
        // Process through each plugin
        var currentBuffer = inputBuffer
        let enabledPlugins = plugins.filter { $0.isEnabled && !$0.isBypassed }
        let totalPlugins = enabledPlugins.count
        var processedCount = 0
        
        print("   Processing through \(totalPlugins) enabled plugins...")
        
        for (pluginIndex, plugin) in enabledPlugins.enumerated() {
            print("   → Processing with: \(plugin.name) (\(plugin.type.rawValue))")
            
            switch plugin.type {
            case .nam:
                // For NAM models, we'd load the .nam file and process
                currentBuffer = try await processWithNAMModel(currentBuffer, modelPath: plugin.path ?? "")
                
            case .audioUnit:
                // Process with loaded Audio Unit - MUST restore presetData for proper sound
                if let auDesc = plugin.componentDescription {
                    currentBuffer = try await processWithAudioUnit(
                        currentBuffer,
                        description: auDesc.toAudioComponentDescription(),
                        presetData: plugin.presetData
                    ) { chunkProgress in
                        // Combine plugin-level and chunk-level progress
                        let pluginBase = Double(pluginIndex) / Double(totalPlugins)
                        let pluginContribution = chunkProgress / Double(totalPlugins)
                        progressHandler(pluginBase + pluginContribution)
                    }
                } else {
                    print("     ⚠️ No component description for plugin \(plugin.name)")
                }
                
            case .impulseResponse:
                // Convolve with impulse response
                currentBuffer = try await processWithImpulseResponse(currentBuffer, irPath: plugin.path ?? "")
            }
            
            processedCount += 1
            progressHandler(Double(processedCount) / Double(totalPlugins))
            print("     ✓ Done (\(processedCount)/\(totalPlugins))")
        }
        
        // Write output
        try outputFile.write(from: currentBuffer)
        print("   ✅ Wrote \(currentBuffer.frameLength) frames to output file")
    }
    
    // MARK: - Private Methods
    
    private func setupNotifications() {
        // Listen for Audio Unit changes
        NotificationCenter.default.publisher(for: NSNotification.Name.AVAudioUnitComponentTagsDidChange)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.scanForAudioUnits()
                }
            }
            .store(in: &cancellables)
    }
    
    private func processWithNAMModel(_ buffer: AVAudioPCMBuffer, modelPath: String) async throws -> AVAudioPCMBuffer {
        // Find and load the NAM Audio Unit
        guard let namComponent = findNAMComponent() else {
            throw AudioUnitError.loadFailed("NAM", "Neural Amp Modeler plugin not found. Please install the NAM Audio Unit.")
        }
        
        // Instantiate NAM Audio Unit
        let namUnit = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AVAudioUnit, Error>) in
            AVAudioUnit.instantiate(with: namComponent.audioComponentDescription, options: .loadOutOfProcess) { unit, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let unit = unit {
                    continuation.resume(returning: unit)
                } else {
                    continuation.resume(throwing: AudioUnitError.loadFailed("NAM", "Failed to instantiate"))
                }
            }
        }
        
        // Load the NAM model file into the Audio Unit
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw AudioUnitError.fileNotFound(modelPath)
        }
        
        // Set the model path via the AU's state dictionary
        var state = namUnit.auAudioUnit.fullState ?? [:]
        state["modelPath"] = modelPath
        state["NAMModelPath"] = modelPath
        state["model"] = modelPath
        namUnit.auAudioUnit.fullState = state
        
        // Process the buffer through NAM using offline rendering
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        
        engine.attach(player)
        engine.attach(namUnit)
        
        engine.connect(player, to: namUnit, format: buffer.format)
        engine.connect(namUnit, to: engine.mainMixerNode, format: buffer.format)
        
        try engine.enableManualRenderingMode(.offline, format: buffer.format, maximumFrameCount: buffer.frameLength)
        try engine.start()
        player.play()
        player.scheduleBuffer(buffer, completionHandler: nil)
        
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
            throw AudioUnitError.bufferCreationFailed
        }
        
        let status = try engine.renderOffline(buffer.frameLength, to: outputBuffer)
        guard status == .success else {
            throw AudioUnitError.renderFailed
        }
        
        engine.stop()
        return outputBuffer
    }
    
    /// Finds the NAM Audio Unit component on the system
    private func findNAMComponent() -> AVAudioUnitComponent? {
        let components = componentManager.components(matching: AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: 0,
            componentManufacturer: 0,
            componentFlags: 0,
            componentFlagsMask: 0
        ))
        
        let namComponent = components.first { component in
            let name = component.name.lowercased()
            let manufacturer = component.manufacturerName.lowercased()
            
            // Check for various NAM naming conventions
            if name.contains("neural amp modeler") { return true }
            if name.contains("neuralampmodeler") { return true }
            if name == "nam" { return true }
            if manufacturer.contains("steven atkinson") { return true }
            if manufacturer.contains("sdatkinson") { return true }
            
            return false
        }
        
        if let found = namComponent {
            print("Found NAM component: \(found.name) by \(found.manufacturerName)")
        }
        
        return namComponent
    }
    
    private func processWithAudioUnit(_ buffer: AVAudioPCMBuffer, description: AudioComponentDescription, presetData: Data?, progressHandler: @escaping (Double) -> Void = { _ in }) async throws -> AVAudioPCMBuffer {
        // IMPORTANT: For offline rendering, we MUST use in-process loading
        // Out-of-process AUs crash with error 4099 during offline rendering
        let options: AudioComponentInstantiationOptions = []
        
        print("     Loading AU in-process for offline rendering...")
        
        let audioUnit = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AVAudioUnit, Error>) in
            AVAudioUnit.instantiate(with: description, options: options) { unit, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let unit = unit {
                    continuation.resume(returning: unit)
                } else {
                    continuation.resume(throwing: AudioUnitError.loadFailed("Unknown", "Failed to instantiate"))
                }
            }
        }
        
        // CRITICAL: Restore plugin state (preset) before processing!
        if let presetData = presetData {
            do {
                if let state = try NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSDictionary.self, NSArray.self, NSString.self, NSNumber.self, NSData.self], from: presetData) as? [String: Any] {
                    audioUnit.auAudioUnit.fullState = state
                    print("     ✓ Restored plugin state from preset data")
                }
            } catch {
                print("     ⚠️ Failed to restore preset: \(error.localizedDescription)")
            }
        } else {
            print("     ⚠️ No preset data - using default plugin settings!")
        }
        
        // Process in chunks like a DAW does when bouncing
        // NAM and other plugins have internal buffer limits
        let chunkSize: AVAudioFrameCount = 4096
        let totalFrames = buffer.frameLength
        
        print("     Processing \(totalFrames) frames in chunks of \(chunkSize)...")
        
        // Create offline render engine
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        
        engine.attach(player)
        engine.attach(audioUnit)
        
        engine.connect(player, to: audioUnit, format: buffer.format)
        engine.connect(audioUnit, to: engine.mainMixerNode, format: buffer.format)
        
        // Enable manual rendering with chunk-sized maximum
        try engine.enableManualRenderingMode(.offline, format: buffer.format, maximumFrameCount: chunkSize)
        try engine.start()
        player.play()
        
        // Schedule the entire buffer - the player will feed it chunk by chunk
        player.scheduleBuffer(buffer, completionHandler: nil)
        
        // Create output buffer for the full file
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: totalFrames) else {
            throw AudioUnitError.bufferCreationFailed
        }
        
        // Create a temporary chunk buffer for rendering
        guard let chunkBuffer = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: chunkSize) else {
            throw AudioUnitError.bufferCreationFailed
        }
        
        var framesRendered: AVAudioFrameCount = 0
        var lastProgressPrint: Double = 0
        
        // Render in chunks
        while framesRendered < totalFrames {
            let framesToRender = min(chunkSize, totalFrames - framesRendered)
            
            let status = try engine.renderOffline(framesToRender, to: chunkBuffer)
            
            if status == .success {
                // Copy chunk to output buffer
                if let outputData = outputBuffer.floatChannelData,
                   let chunkData = chunkBuffer.floatChannelData {
                    let channelCount = Int(buffer.format.channelCount)
                    for channel in 0..<channelCount {
                        let destOffset = Int(framesRendered)
                        memcpy(outputData[channel].advanced(by: destOffset),
                               chunkData[channel],
                               Int(chunkBuffer.frameLength) * MemoryLayout<Float>.size)
                    }
                }
                framesRendered += chunkBuffer.frameLength
            } else if status == .insufficientDataFromInputNode {
                // No more data from player - we're done
                break
            } else if status == .cannotDoInCurrentContext {
                // Try again
                try await Task.sleep(for: .milliseconds(1))
                continue
            } else {
                throw AudioUnitError.renderFailed
            }
            
            // Progress reporting
            let progress = Double(framesRendered) / Double(totalFrames)
            
            // Update UI progress
            await MainActor.run {
                progressHandler(progress)
            }
            
            // Console logging (every 10%)
            if progress - lastProgressPrint >= 0.1 {
                print("     Progress: \(Int(progress * 100))%")
                lastProgressPrint = progress
            }
        }
        
        outputBuffer.frameLength = framesRendered
        engine.stop()
        
        print("     ✓ Rendered \(framesRendered) frames")
        return outputBuffer
    }
    
    private func processWithImpulseResponse(_ buffer: AVAudioPCMBuffer, irPath: String) async throws -> AVAudioPCMBuffer {
        if AppSettings.shared.usePreferredIRLoader,
           let irLoaderDesc = AppSettings.shared.preferredIRLoader {
            print("   Using Preferred IR Loader AU: \(irPath.components(separatedBy: "/").last ?? "")")
            return try await processWithIRAudioUnit(buffer, description: irLoaderDesc.toAudioComponentDescription(), irPath: irPath)
        }

        // Load the impulse response file
        guard FileManager.default.fileExists(atPath: irPath) else {
            throw AudioUnitError.fileNotFound(irPath)
        }
        
        let irURL = URL(fileURLWithPath: irPath)
        let irFile = try AVAudioFile(forReading: irURL)
        let irFormat = irFile.processingFormat
        let irFrameCount = AVAudioFrameCount(irFile.length)
        
        guard let irBuffer = AVAudioPCMBuffer(pcmFormat: irFormat, frameCapacity: irFrameCount) else {
            throw AudioUnitError.bufferCreationFailed
        }
        try irFile.read(into: irBuffer)
        
        // Perform real convolution using vDSP
        return try convolve(input: buffer, withIR: irBuffer)
    }
    
    /// Performs real convolution of input audio with an impulse response using vDSP
    private func convolve(input: AVAudioPCMBuffer, withIR ir: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard let inputData = input.floatChannelData,
              let irData = ir.floatChannelData else {
            throw AudioUnitError.bufferCreationFailed
        }
        
        let inputLength = Int(input.frameLength)
        let irLength = Int(ir.frameLength)
        let outputLength = inputLength + irLength - 1
        let channelCount = Int(input.format.channelCount)
        
        // Create output buffer
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: input.format, frameCapacity: AVAudioFrameCount(outputLength)) else {
            throw AudioUnitError.bufferCreationFailed
        }
        outputBuffer.frameLength = AVAudioFrameCount(outputLength)
        
        guard let outputData = outputBuffer.floatChannelData else {
            throw AudioUnitError.bufferCreationFailed
        }
        
        // Convolve each channel
        for channel in 0..<channelCount {
            let inputChannel = inputData[channel]
            // Use first channel of IR if IR has fewer channels
            let irChannel = irData[min(channel, Int(ir.format.channelCount) - 1)]
            let outputChannel = outputData[channel]
            
            // Zero out output buffer
            vDSP_vclr(outputChannel, 1, vDSP_Length(outputLength))
            
            // Perform convolution using vDSP_conv
            // vDSP_conv performs: output[n] = sum(input[n+k] * ir[k])
            // We need to flip the IR for proper convolution
            var flippedIR = [Float](repeating: 0, count: irLength)
            var irCopy = [Float](UnsafeBufferPointer(start: irChannel, count: irLength))
            vDSP_vrvrs(&irCopy, 1, vDSP_Length(irLength))
            flippedIR = irCopy
            
            // Use vDSP_conv for convolution
            // The filter needs to be padded for vDSP_conv
            vDSP_conv(inputChannel, 1,
                      flippedIR, 1,
                      outputChannel, 1,
                      vDSP_Length(outputLength),
                      vDSP_Length(irLength))
        }
        
        // Normalize to prevent clipping (find peak and scale if needed)
        for channel in 0..<channelCount {
            var peak: Float = 0
            vDSP_maxmgv(outputData[channel], 1, &peak, vDSP_Length(outputLength))
            
            if peak > 1.0 {
                var scale = 1.0 / peak
                vDSP_vsmul(outputData[channel], 1, &scale, outputData[channel], 1, vDSP_Length(outputLength))
            }
        }
        
        // Trim to original input length (or keep full convolution tail)
        // For cabinet IRs, we typically want to keep the tail
        // But for practical purposes, we'll return a buffer matching input length + reasonable tail
        let practicalLength = min(outputLength, inputLength + min(irLength, 48000)) // Max 1 second tail at 48kHz
        
        guard let finalBuffer = AVAudioPCMBuffer(pcmFormat: input.format, frameCapacity: AVAudioFrameCount(practicalLength)) else {
            throw AudioUnitError.bufferCreationFailed
        }
        finalBuffer.frameLength = AVAudioFrameCount(practicalLength)
        
        if let finalData = finalBuffer.floatChannelData {
            for channel in 0..<channelCount {
                memcpy(finalData[channel], outputData[channel], practicalLength * MemoryLayout<Float>.size)
            }
        }
        
        return finalBuffer
    }
    
    /// Processes using a dedicated AU for IR loading
    private func processWithIRAudioUnit(_ buffer: AVAudioPCMBuffer, description: AudioComponentDescription, irPath: String) async throws -> AVAudioPCMBuffer {
        guard FileManager.default.fileExists(atPath: irPath) else {
            throw AudioUnitError.fileNotFound(irPath)
        }
        
        // For offline rendering
        let options: AudioComponentInstantiationOptions = []
        
        let audioUnit = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AVAudioUnit, Error>) in
            AVAudioUnit.instantiate(with: description, options: options) { unit, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let unit = unit {
                    continuation.resume(returning: unit)
                } else {
                    continuation.resume(throwing: AudioUnitError.loadFailed("IR Loader", "Failed to instantiate"))
                }
            }
        }
        
        // Try to load the IR file into the AU state
        // We attempt common keys used by plugins (including our NAM plugin)
        var state = audioUnit.auAudioUnit.fullState ?? [:]
        state["IRPath"] = irPath          // NAM Plugin key
        state["impulseResponse"] = irPath
        state["irFile"] = irPath
        state["file"] = irPath
        state["path"] = irPath
        audioUnit.auAudioUnit.fullState = state
        
        // Process offline
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        
        engine.attach(player)
        engine.attach(audioUnit)
        
        engine.connect(player, to: audioUnit, format: buffer.format)
        engine.connect(audioUnit, to: engine.mainMixerNode, format: buffer.format)
        
        try engine.enableManualRenderingMode(.offline, format: buffer.format, maximumFrameCount: buffer.frameLength)
        try engine.start()
        player.play()
        player.scheduleBuffer(buffer, completionHandler: nil)
        
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
            throw AudioUnitError.bufferCreationFailed
        }
        
        let status = try engine.renderOffline(buffer.frameLength, to: outputBuffer)
        guard status == .success else {
            throw AudioUnitError.renderFailed
        }
        
        engine.stop()
        return outputBuffer
    }
}

// MARK: - Errors

enum AudioUnitError: LocalizedError {
    case loadFailed(String, String)
    case engineNotInitialized
    case bufferCreationFailed
    case renderFailed
    case fileNotFound(String)
    
    var errorDescription: String? {
        switch self {
        case .loadFailed(let name, let reason):
            return "Failed to load Audio Unit '\(name)': \(reason)"
        case .engineNotInitialized:
            return "Audio engine not initialized"
        case .bufferCreationFailed:
            return "Failed to create audio buffer"
        case .renderFailed:
            return "Audio rendering failed"
        case .fileNotFound(let path):
            return "Audio file not found: \(path)"
        }
    }
}
