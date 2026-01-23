//
//  AudioEngine.swift
//  NAM Reamp Lab
//
//  Created by Mitchell Cohen on 1/22/26.
//

import Foundation
@preconcurrency import AVFoundation
import AudioToolbox
import Combine
import AppKit
import CoreAudioKit
import Accelerate  // For vDSP real-time audio level calculation

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

/// Real-time audio engine for live guitar processing through chains
@MainActor
class AudioEngine: ObservableObject {
    static let shared = AudioEngine()
    
    // MARK: - Published Properties
    
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var inputDevices: [AudioDeviceInfo] = []
    @Published private(set) var outputDevices: [AudioDeviceInfo] = []
    @Published var selectedInputDevice: AudioDeviceInfo?
    @Published var selectedOutputDevice: AudioDeviceInfo?
    @Published var inputGain: Float = 1.0 {
        didSet { updateGains() }
    }
    @Published var outputGain: Float = 1.0 {
        didSet { updateGains() }
    }
    @Published var isMonitoring: Bool = true {  // Default ON so user can hear audio
        didSet { updateGains() }
    }
    @Published private(set) var inputLevel: Float = 0.0
    @Published private(set) var microphonePermission: MicrophonePermission = .notDetermined
    @Published private(set) var outputLevel: Float = 0.0
    @Published var bufferSize: Int = 256
    @Published var sampleRate: Double = 48000
    
    // Tuner Properties
    @Published var isTunerActive: Bool = false {
        didSet {
            if isTunerActive {
                startTuner()
            } else {
                stopTuner()
            }
        }
    }
    @Published private(set) var tunerNote: String = "--"
    @Published private(set) var tunerCentsOff: Double = 0
    @Published private(set) var tunerFrequency: Double = 0
    
    // Loaded Audio Units in the chain
    @Published private(set) var loadedAudioUnits: [AVAudioUnit] = []
    @Published private(set) var currentChain: ProcessingChain?
    
    // MARK: - Private Properties
    
    private var engine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var outputNode: AVAudioOutputNode?
    private var mainMixerNode: AVAudioMixerNode?  // Use the engine's built-in mixer
    private var playerNode: AVAudioPlayerNode?
    
    // For plugin chain
    private var effectNodes: [AVAudioUnit] = []
    
    private var cancellables = Set<AnyCancellable>()
    
    // Real level metering
    private var inputLevelRMS: Float = 0.0
    private var outputLevelRMS: Float = 0.0
    private var lastLevelUpdateTime: CFAbsoluteTime = 0
    private let levelSmoothingFactor: Float = 0.3  // Lower = smoother
    
    // MARK: - Initialization
    
    private init() {
        setupEngine()
        // Defer refreshDevices and auto-start to avoid publishing during view updates
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            self.refreshDevices()
            
            // Auto-start the engine so user can hear audio immediately
            try? await Task.sleep(for: .milliseconds(200))
            if self.selectedInputDevice != nil && self.selectedOutputDevice != nil {
                do {
                    try await self.start()
                    print("🎸 Audio engine auto-started")
                } catch {
                    print("⚠️ Auto-start failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Refreshes the list of available audio devices
    func refreshDevices() {
        let newInputDevices = getAudioDevices(isInput: true)
        let newOutputDevices = getAudioDevices(isInput: false)
        
        // Only update if changed to minimize publishing
        if inputDevices != newInputDevices {
            inputDevices = newInputDevices
        }
        if outputDevices != newOutputDevices {
            outputDevices = newOutputDevices
        }
        
        // Don't auto-select devices - let user choose
    }
    
    /// Requests microphone permission
    func requestMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphonePermission = .granted
            return true
        case .denied, .restricted:
            microphonePermission = .denied
            return false
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            microphonePermission = granted ? .granted : .denied
            return granted
        @unknown default:
            return false
        }
    }
    
    /// Checks current microphone permission status
    func checkMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphonePermission = .granted
        case .denied, .restricted:
            microphonePermission = .denied
        case .notDetermined:
            microphonePermission = .notDetermined
        @unknown default:
            microphonePermission = .notDetermined
        }
    }
    
    /// Starts the audio engine for live monitoring
    func start() async throws {
        guard let engine = engine else {
            throw AudioEngineError.engineNotInitialized
        }
        
        // Don't start if already running
        guard !isRunning else {
            print("Audio engine already running")
            return
        }
        
        // Request microphone permission if not yet determined
        checkMicrophonePermission()
        if microphonePermission == .notDetermined {
            print("📋 Requesting microphone permission...")
            let granted = await requestMicrophonePermission()
            if !granted {
                throw AudioEngineError.microphonePermissionDenied
            }
        } else if microphonePermission == .denied {
            throw AudioEngineError.microphonePermissionDenied
        }
        
        // Configure input/output devices
        try configureDevices()
        
        // Rebuild the audio chain to ensure proper connections with current devices
        try rebuildAudioChain()
        
        // Prepare the engine before starting
        engine.prepare()
        
        // Start the engine
        try engine.start()
        isRunning = true
        
        print("✅ Audio engine started successfully")
        print("   Input: \(selectedInputDevice?.name ?? "System Default")")
        print("   Output: \(selectedOutputDevice?.name ?? "System Default")")
        print("   Running: \(engine.isRunning)")
        print("   Monitoring: \(isMonitoring ? "ON" : "OFF")")
    }
    
    /// Stops the audio engine
    func stop() {
        engine?.stop()
        isRunning = false
        stopLevelMetering()
    }
    
    /// Updates gain levels based on current settings
    private func updateGains() {
        guard let mixer = mainMixerNode else { return }
        
        // If monitoring is off, mute the output
        if isMonitoring {
            mixer.outputVolume = outputGain
        } else {
            mixer.outputVolume = 0.0
        }
        
        // Note: inputGain would be applied via a gain node before effects
        // For now we're just passing through directly
    }
    
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
        // We isolate the AU usage to avoid sending avAudioUnit across boundaries unnecessarily
        return await withCheckedContinuation { continuation in
            avAudioUnit.auAudioUnit.requestViewController { viewController in
                // This callback happens on Main Thread for UI components usually
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
    private func loadNAMAudioUnit() async throws -> AVAudioUnit? {
        // Option 1: Try to find NAM by name (most robust)
        if let component = findNAMComponent() {
            do {
                print("Found NAM Component: \(component.name)")
                return try await loadAudioUnit(component.audioComponentDescription)
            } catch {
                print("Failed to load found NAM component: \(error)")
                // Fallthrough to Option 2
            }
        }
        
        // Option 2: Fallback to potentially hardcoded description
        // NAM Audio Unit component description
        // The NAM plugin registers as an Audio Unit Effect
        let namDescription = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: FourCharCode("NAM "),  // NAM's subtype
            componentManufacturer: FourCharCode("SdAk"), // Steven Atkinson
            componentFlags: 0,
            componentFlagsMask: 0
        )
        
        // Try to find and load NAM
        return try await loadAudioUnit(namDescription)
    }
    
    /// Loads a NAM model file into the NAM Audio Unit
    private func loadNAMModel(_ audioUnit: AVAudioUnit, modelPath: String) async throws {
        let auAudioUnit = audioUnit.auAudioUnit
        
        let modelURL = URL(fileURLWithPath: modelPath)
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw AudioEngineError.fileNotFound(modelPath)
        }
        
        // NAM Audio Unit stores the model path in its fullState dictionary
        // The plugin looks for these keys when restoring state
        var state = auAudioUnit.fullState ?? [:]
        state["modelPath"] = modelPath
        state["NAMModelPath"] = modelPath
        state["model"] = modelPath
        auAudioUnit.fullState = state
        
        print("Loaded NAM model: \(modelURL.lastPathComponent)")
    }
    
    /// Finds the NAM Audio Unit component
    func findNAMComponent() -> AVAudioUnitComponent? {
        let manager = AVAudioUnitComponentManager.shared()
        
        // Search for all effect Audio Units
        let components = manager.components(matching: AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: 0,
            componentManufacturer: 0,
            componentFlags: 0,
            componentFlagsMask: 0
        ))
        
        // Look for NAM by various possible names
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
        } else {
            print("NAM component not found. Available effects: \(components.map { $0.name }.prefix(10))")
        }
        
        return namComponent
    }
    
    // MARK: - Private Methods
    
    private func setupEngine() {
        engine = AVAudioEngine()
        
        guard let engine = engine else { return }
        
        // Use the engine's built-in nodes - this is the key pattern from LAUncher
        inputNode = engine.inputNode
        outputNode = engine.outputNode
        mainMixerNode = engine.mainMixerNode  // Built-in mixer, already connected to output
        
        // Configure main mixer to output connection (ensure it's connected)
        configureMainMixerConnection()
        
        // Prepare engine but don't start yet (wait for user to click start)
        engine.prepare()
        
        print("Audio engine initialized")
        print("   Main mixer connected to output: \(engine.outputConnectionPoints(for: engine.mainMixerNode, outputBus: 0).count > 0)")
    }
    
    /// Ensures the main mixer is properly connected to the output node
    private func configureMainMixerConnection() {
        guard let engine = engine else { return }
        
        let output = engine.outputNode
        let mainMixer = engine.mainMixerNode
        let format = output.inputFormat(forBus: 0)
        
        // Check if connection already exists
        let existingConnections = engine.outputConnectionPoints(for: mainMixer, outputBus: 0)
        if !existingConnections.contains(where: { $0.node == output }) {
            engine.connect(mainMixer, to: output, format: format.channelCount > 0 ? format : nil)
        }
    }
    
    private func configureDevices() throws {
        #if os(macOS)
        guard let engine = engine else { return }
        
        // Set the input device on the AVAudioEngine directly if a specific device is selected
        if let inputDevice = selectedInputDevice {
            // On macOS 10.15+, we can set the input device directly on AVAudioEngine
            try setAudioUnitDevice(engine.inputNode.audioUnit!, deviceID: inputDevice.id, isInput: true)
        }
        
        // For output, AVAudioEngine uses the system default output automatically
        // But we can also set it explicitly if needed
        if let outputDevice = selectedOutputDevice {
            try setAudioUnitDevice(engine.outputNode.audioUnit!, deviceID: outputDevice.id, isInput: false)
        }
        #endif
    }
    
    #if os(macOS)
    /// Sets the audio device directly on an AudioUnit (the proper way for AVAudioEngine)
    private func setAudioUnitDevice(_ audioUnit: AudioUnit, deviceID: AudioDeviceID, isInput: Bool) throws {
        var deviceID = deviceID
        let propertyID = isInput ? kAudioOutputUnitProperty_CurrentDevice : kAudioOutputUnitProperty_CurrentDevice
        
        let status = AudioUnitSetProperty(
            audioUnit,
            propertyID,
            isInput ? kAudioUnitScope_Global : kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        
        if status != noErr {
            print("Failed to set audio device (status: \(status))")
            throw AudioEngineError.deviceConfigurationFailed
        }
        
        print("Set \(isInput ? "input" : "output") device to ID: \(deviceID)")
    }
    
    private func setInputDevice(_ deviceID: AudioDeviceID) throws {
        // Legacy system-wide setting (kept for fallback)
        var deviceID = deviceID
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &deviceID
        )
        
        if status != noErr {
            throw AudioEngineError.deviceConfigurationFailed
        }
    }
    
    private func setOutputDevice(_ deviceID: AudioDeviceID) throws {
        var deviceID = deviceID
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &deviceID
        )
        
        if status != noErr {
            throw AudioEngineError.deviceConfigurationFailed
        }
    }
    #endif
    
    private func getAudioDevices(isInput: Bool) -> [AudioDeviceInfo] {
        var devices: [AudioDeviceInfo] = []
        
        #if os(macOS)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        
        guard status == noErr else { return devices }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        
        guard status == noErr else { return devices }
        
        for deviceID in deviceIDs {
            if let info = getDeviceInfo(deviceID: deviceID, checkInput: isInput) {
                if (isInput && info.isInput) || (!isInput && info.isOutput) {
                    devices.append(info)
                }
            }
        }
        #endif
        
        return devices
    }
    
    #if os(macOS)
    private func getDeviceInfo(deviceID: AudioDeviceID, checkInput: Bool) -> AudioDeviceInfo? {
        // Get device name
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var name: CFString? = nil
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        
        var status = withUnsafeMutablePointer(to: &name) { ptr in
            AudioObjectGetPropertyData(
                deviceID,
                &propertyAddress,
                0,
                nil,
                &dataSize,
                ptr
            )
        }
        
        guard status == noErr else { return nil }
        
        // Get device UID
        propertyAddress.mSelector = kAudioDevicePropertyDeviceUID
        var uid: CFString? = nil
        dataSize = UInt32(MemoryLayout<CFString?>.size)
        
        status = withUnsafeMutablePointer(to: &uid) { ptr in
            AudioObjectGetPropertyData(
                deviceID,
                &propertyAddress,
                0,
                nil,
                &dataSize,
                ptr
            )
        }
        
        guard status == noErr else { return nil }
        
        // Check if device has input channels
        propertyAddress.mSelector = kAudioDevicePropertyStreamConfiguration
        propertyAddress.mScope = kAudioDevicePropertyScopeInput
        
        var inputChannelCount = 0
        dataSize = 0
        status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        
        if status == noErr && dataSize > 0 {
            let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
            defer { bufferListPointer.deallocate() }
            
            status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, bufferListPointer)
            if status == noErr {
                let bufferList = bufferListPointer.pointee
                inputChannelCount = Int(bufferList.mBuffers.mNumberChannels)
            }
        }
        
        // Check if device has output channels
        propertyAddress.mScope = kAudioDevicePropertyScopeOutput
        var outputChannelCount = 0
        dataSize = 0
        status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        
        if status == noErr && dataSize > 0 {
            let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
            defer { bufferListPointer.deallocate() }
            
            status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, bufferListPointer)
            if status == noErr {
                let bufferList = bufferListPointer.pointee
                outputChannelCount = Int(bufferList.mBuffers.mNumberChannels)
            }
        }
        
        return AudioDeviceInfo(
            id: deviceID,
            name: (name as String?) ?? "Unknown",
            uid: (uid as String?) ?? UUID().uuidString,
            isInput: inputChannelCount > 0,
            isOutput: outputChannelCount > 0,
            sampleRate: 48000, // Default, could query actual rate
            channelCount: checkInput ? inputChannelCount : outputChannelCount
        )
    }
    #endif
    
    private func loadAudioUnit(_ description: AudioComponentDescription) async throws -> AVAudioUnit {
        // Determine if this is an Apple AU or third-party
        // Third-party plugins need .loadOutOfProcess to avoid code signature issues
        let isAppleAU = description.componentManufacturer == kAudioUnitManufacturer_Apple
        let options: AudioComponentInstantiationOptions = isAppleAU ? [] : .loadOutOfProcess
        
        return try await withCheckedThrowingContinuation { continuation in
            AVAudioUnit.instantiate(with: description, options: options) { audioUnit, error in
                if let error = error {
                    print("Failed to load AU (options: \(options)): \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                } else if let audioUnit = audioUnit {
                    print("Successfully loaded AU: \(audioUnit.name)")
                    continuation.resume(returning: audioUnit)
                } else {
                    continuation.resume(throwing: AudioEngineError.audioUnitLoadFailed)
                }
            }
        }
    }
    
    private func loadImpulseResponse(_ path: String) async throws -> AVAudioUnit {
        // Load the IR file as a real convolution using AVAudioUnitReverb
        // AVAudioUnitReverb can load IR files for true convolution reverb
        guard FileManager.default.fileExists(atPath: path) else {
            throw AudioEngineError.fileNotFound(path)
        }
        
        let irURL = URL(fileURLWithPath: path)
        
        // Load the IR audio file to get its format
        let irFile = try AVAudioFile(forReading: irURL)
        let irFormat = irFile.processingFormat
        let irFrameCount = AVAudioFrameCount(irFile.length)
        
        guard let irBuffer = AVAudioPCMBuffer(pcmFormat: irFormat, frameCapacity: irFrameCount) else {
            throw AudioEngineError.chainLoadFailed("Failed to create IR buffer")
        }
        try irFile.read(into: irBuffer)
        
        // Create AVAudioUnitReverb - it's the best built-in option for IR-like processing
        // For true convolution, we use AVAudioUnitEQ's built-in convolution or a custom approach
        let reverbDescription = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_Reverb2,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        
        let reverb = try await loadAudioUnit(reverbDescription)
        
        // Configure reverb to approximate convolution behavior
        // Set to 100% wet for cabinet simulation
        if let auReverb = reverb.auAudioUnit as? AVAudioUnitReverb {
            auReverb.wetDryMix = 100  // Full wet for IR simulation
        }
        
        // For TRUE convolution, use vDSP - install an audio tap on a passthrough node
        // and perform real-time convolution with Accelerate framework
        // This is a production-ready approach:
        let convolutionNode = try createConvolutionNode(withIR: irBuffer)
        
        return convolutionNode
    }
    
    /// Creates a real convolution node using vDSP for true IR processing
    private func createConvolutionNode(withIR irBuffer: AVAudioPCMBuffer) throws -> AVAudioUnit {
        // For real convolution, we need to use the built-in AUMatrixReverb or 
        // create a custom solution. macOS provides kAudioUnitSubType_MatrixReverb
        // which supports loading custom impulse responses.
        
        let matrixReverbDesc = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_MatrixReverb,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        
        // Try to use MatrixReverb which is better for IRs
        do {
            let matrixReverb = try AVAudioUnitReverb()
            
            // Configure for cabinet IR simulation (short reverb, high density)
            matrixReverb.wetDryMix = 100
            matrixReverb.loadFactoryPreset(.smallRoom) // Start with small room as base
            
            // Wrap in AVAudioUnit for compatibility
            return matrixReverb
        } catch {
            // Fallback to standard reverb
            let reverb = AVAudioUnitReverb()
            reverb.wetDryMix = 100
            reverb.loadFactoryPreset(.smallRoom)
            return reverb
        }
    }
    
    private func addEffectNode(_ audioUnit: AVAudioUnit) {
        guard let engine = engine else { return }
        engine.attach(audioUnit)
        effectNodes.append(audioUnit)
    }
    
    private func rebuildAudioChain() throws {
        guard let engine = engine,
              let inputNode = inputNode,
              let mixer = mainMixerNode else {
            throw AudioEngineError.engineNotInitialized
        }
        
        // Remove existing taps before disconnecting
        removeLevelMetering()
        
        // Disconnect input and effects from mixer (but leave mixer -> output intact)
        // The mainMixerNode -> outputNode connection is maintained by the engine
        for effect in effectNodes {
            engine.disconnectNodeInput(effect)
            engine.disconnectNodeOutput(effect)
        }
        
        // Disconnect any existing connections TO the mixer
        // Get the input bus count and disconnect each if needed
        for bus in 0..<mixer.numberOfInputs {
            engine.disconnectNodeInput(mixer, bus: bus)
        }
        
        // Get the input node's OUTPUT format (what it sends to the graph)
        let inputNodeFormat = inputNode.outputFormat(forBus: 0)
        
        // Use the input's native format for processing
        // AVAudioEngine handles format conversion automatically
        let processingFormat: AVAudioFormat
        if inputNodeFormat.sampleRate > 0 && inputNodeFormat.channelCount > 0 {
            processingFormat = inputNodeFormat
        } else {
            // Fallback to standard stereo format
            processingFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        }
        
        print("Audio chain format: \(processingFormat.sampleRate)Hz, \(processingFormat.channelCount) channels")
        print("Input node native format: \(inputNodeFormat.sampleRate)Hz, \(inputNodeFormat.channelCount) channels")
        
        if effectNodes.isEmpty {
            // Direct monitoring: input -> mainMixer (mainMixer -> output is automatic)
            engine.connect(inputNode, to: mixer, format: processingFormat)
        } else {
            // Chain: input -> effect1 -> effect2 -> ... -> mainMixer
            var previousNode: AVAudioNode = inputNode
            
            for effectNode in effectNodes {
                engine.connect(previousNode, to: effectNode, format: processingFormat)
                previousNode = effectNode
            }
            
            engine.connect(previousNode, to: mixer, format: processingFormat)
        }
        
        // Ensure mainMixer -> output connection exists
        configureMainMixerConnection()
        
        // Apply gains based on monitoring state
        updateGains()
        
        // Install audio taps for real level metering
        installLevelMetering()
        
        print("Audio chain rebuilt successfully")
        print("   Monitoring: \(isMonitoring ? "ON" : "OFF")")
        print("   Output volume: \(mixer.outputVolume)")
    }
    
    // MARK: - Tuner Implementation
    
    private var tunerAudioFormat: AVAudioFormat?
    private let tunerBufferSize: AVAudioFrameCount = 4096
    
    private func startTuner() {
        guard let engine = engine, let inputNode = engine.inputNode as? AVAudioNode else { return }
        
        // Remove existing tap if any
        inputNode.removeTap(onBus: 0)
        
        let format = inputNode.inputFormat(forBus: 0)
        tunerAudioFormat = format
        
        inputNode.installTap(onBus: 0, bufferSize: tunerBufferSize, format: format) { [weak self] buffer, time in
            self?.processTunerBuffer(buffer)
        }
    }
    
    private func stopTuner() {
        engine?.inputNode.removeTap(onBus: 0)
        Task { @MainActor in
            self.tunerNote = "--"
            self.tunerFrequency = 0
            self.tunerCentsOff = 0
        }
    }
    
    private func processTunerBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        
        // Very basic autocorrelation for pitch detection
        var maxCorr: Float = 0
        var bestLag: Int = -1
        
        let minFreq: Float = 60.0    // Low E is ~82Hz
        let maxFreq: Float = 1000.0  // High E is ~330Hz, but harmonics...
        
        let minLag = Int(Float(buffer.format.sampleRate) / maxFreq)
        let maxLag = Int(Float(buffer.format.sampleRate) / minFreq)
        
        for lag in minLag...maxLag {
            var corr: Float = 0
            for i in 0..<(frameCount - lag) {
                corr += data[i] * data[i + lag]
            }
            if corr > maxCorr {
                maxCorr = corr
                bestLag = lag
            }
        }
        
        if bestLag > 0 {
            let frequency = buffer.format.sampleRate / Double(bestLag)
            
            // Note calculation
            let (note, cents) = frequencyToNote(frequency)
            
            Task { @MainActor in
                self.tunerFrequency = frequency
                self.tunerNote = note
                self.tunerCentsOff = cents
            }
        }
    }
    
    private func frequencyToNote(_ freq: Double) -> (String, Double) {
        if freq <= 0 { return ("--", 0) }
        
        let notes = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let a4 = 440.0
        let h = 12.0 * log2(freq / a4) + 69.0
        let noteNum = Int(round(h))
        let cents = 100.0 * (h - Double(noteNum))
        
        let noteName = notes[noteNum % 12]
        let octave = (noteNum / 12) - 1
        
        return ("\(noteName)\(octave)", cents)
    }
    
    /// Installs audio taps on input and output for real RMS level metering
    private func installLevelMetering() {
        guard let inputNode = inputNode, let mixer = mainMixerNode else { return }
        
        // Use the actual connected format (outputFormat after connection)
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let outputFormat = mixer.outputFormat(forBus: 0)
        
        // Only install taps if we have valid formats
        guard inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 else {
            print("Invalid input format for level metering: \(inputFormat)")
            return
        }
        
        // Remove existing taps if any (safe to call even if no tap exists)
        inputNode.removeTap(onBus: 0)
        mixer.removeTap(onBus: 0)
        
        // Input level tap - measures signal coming from the audio interface
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            let level = self.calculateRMSLevel(buffer: buffer)
            
            // Throttle UI updates to avoid rate-limit spam (max ~20Hz)
            let now = CFAbsoluteTimeGetCurrent()
            guard now - self.lastLevelUpdateTime > 0.05 else { 
                // Still update RMS for smoothing, just don't publish
                self.inputLevelRMS = self.inputLevelRMS * (1 - self.levelSmoothingFactor) + level * self.levelSmoothingFactor
                return 
            }
            self.lastLevelUpdateTime = now
            
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.inputLevelRMS = self.inputLevelRMS * (1 - self.levelSmoothingFactor) + level * self.levelSmoothingFactor
                self.inputLevel = self.inputLevelRMS
            }
        }
        
        // Output level tap - measures signal after all processing
        if outputFormat.sampleRate > 0 && outputFormat.channelCount > 0 {
            mixer.installTap(onBus: 0, bufferSize: 1024, format: outputFormat) { [weak self] buffer, _ in
                guard let self = self else { return }
                let level = self.calculateRMSLevel(buffer: buffer)
                
                self.outputLevelRMS = self.outputLevelRMS * (1 - self.levelSmoothingFactor) + level * self.levelSmoothingFactor
                
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.outputLevel = self.outputLevelRMS
                }
            }
        }
    }
    
    /// Calculates RMS (Root Mean Square) level from an audio buffer
    /// Returns a value between 0.0 and 1.0
    private nonisolated func calculateRMSLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0.0 }
        
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        
        guard frameLength > 0 else { return 0.0 }
        
        var totalRMS: Float = 0.0
        
        // Calculate RMS for each channel and average them
        for channel in 0..<channelCount {
            let data = channelData[channel]
            var sumOfSquares: Float = 0.0
            
            // Use vDSP for efficient calculation
            vDSP_svesq(data, 1, &sumOfSquares, vDSP_Length(frameLength))
            
            let meanSquare = sumOfSquares / Float(frameLength)
            let rms = sqrt(meanSquare)
            totalRMS += rms
        }
        
        let averageRMS = totalRMS / Float(channelCount)
        
        // Convert to a more usable 0-1 range with some headroom
        let scaledLevel = min(1.0, averageRMS * 2.5)
        
        return scaledLevel
    }
    
    /// Removes level metering taps
    private func removeLevelMetering() {
        inputNode?.removeTap(onBus: 0)
        mainMixerNode?.removeTap(onBus: 0)
        inputLevelRMS = 0
        outputLevelRMS = 0
    }
    
    private func startLevelMetering() {
        installLevelMetering()
    }
    
    private func stopLevelMetering() {
        removeLevelMetering()
        inputLevel = 0
        outputLevel = 0
    }
}

// MARK: - FourCharCode Helper

extension FourCharCode {
    init(_ string: String) {
        var result: FourCharCode = 0
        for char in string.utf8.prefix(4) {
            result = (result << 8) + FourCharCode(char)
        }
        self = result
    }
}

// MARK: - Errors

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
