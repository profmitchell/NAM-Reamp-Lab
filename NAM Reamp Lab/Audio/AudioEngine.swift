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

/// Real-time audio engine for live guitar processing through chains
@MainActor
class AudioEngine: ObservableObject {
    static let shared = AudioEngine()
    
    // MARK: - Published Properties
    
    @Published var isRunning: Bool = false
    @Published var inputDevices: [AudioDeviceInfo] = []
    @Published var outputDevices: [AudioDeviceInfo] = []
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
    @Published var inputLevel: Float = 0.0
    @Published var microphonePermission: MicrophonePermission = .notDetermined
    @Published var outputLevel: Float = 0.0
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
    @Published var tunerNote: String = "--"
    @Published var tunerCentsOff: Double = 0
    @Published var tunerFrequency: Double = 0
    
    internal let tunerManager = TunerManager()
    
    // Loaded Audio Units in the chain
    @Published var loadedAudioUnits: [AVAudioUnit] = []
    @Published var currentChain: ProcessingChain?
    
    // MARK: - Properties used by extensions
    
    internal var engine: AVAudioEngine?
    internal var inputNode: AVAudioInputNode?
    internal var outputNode: AVAudioOutputNode?
    internal var mainMixerNode: AVAudioMixerNode?
    internal var playerNode: AVAudioPlayerNode?
    
    internal var effectNodes: [AVAudioUnit] = []
    internal var cancellables = Set<AnyCancellable>()
    
    // Real level metering
    internal var inputLevelRMS: Float = 0.0
    internal var outputLevelRMS: Float = 0.0
    internal var lastLevelUpdateTime: CFAbsoluteTime = 0
    internal let levelSmoothingFactor: Float = 0.3
    
    // MARK: - Initialization
    
    private init() {
        setupTunerBindings()
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
    
    // MARK: - Core Lifecycle
    
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
        
        guard !isRunning else { return }
        
        checkMicrophonePermission()
        if microphonePermission == .notDetermined {
            let granted = await requestMicrophonePermission()
            if !granted {
                throw AudioEngineError.microphonePermissionDenied
            }
        } else if microphonePermission == .denied {
            throw AudioEngineError.microphonePermissionDenied
        }
        
        try configureDevices()
        try rebuildAudioChain()
        
        engine.prepare()
        try engine.start()
        isRunning = true
    }
    
    /// Stops the audio engine
    func stop() {
        engine?.stop()
        isRunning = false
        stopLevelMetering()
    }
    
    /// Updates gain levels based on current settings
    internal func updateGains() {
        guard let mixer = mainMixerNode else { return }
        
        if isMonitoring {
            mixer.outputVolume = outputGain
        } else {
            mixer.outputVolume = 0.0
        }
    }
    
    internal func setupEngine() {
        engine = AVAudioEngine()
        guard let engine = engine else { return }
        
        inputNode = engine.inputNode
        outputNode = engine.outputNode
        mainMixerNode = engine.mainMixerNode
        
        configureMainMixerConnection()
        engine.prepare()
        
        print("Audio engine initialized")
    }
    
    internal func configureMainMixerConnection() {
        guard let engine = engine else { return }
        let output = engine.outputNode
        let mainMixer = engine.mainMixerNode
        let format = output.inputFormat(forBus: 0)
        
        let existingConnections = engine.outputConnectionPoints(for: mainMixer, outputBus: 0)
        if !existingConnections.contains(where: { $0.node == output }) {
            engine.connect(mainMixer, to: output, format: format.channelCount > 0 ? format : nil)
        }
    }
    
    // MARK: - Tuner Bindings
    
    internal func setupTunerBindings() {
        tunerManager.$noteName.assign(to: &$tunerNote)
        tunerManager.$centsOff.assign(to: &$tunerCentsOff)
        tunerManager.$frequency.assign(to: &$tunerFrequency)
    }
    
    internal func startTuner() {
        guard let inputNode = inputNode else { return }
        let format = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 1, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.tunerManager.processBuffer(buffer)
        }
    }
    
    internal func stopTuner() {
        inputNode?.removeTap(onBus: 1)
        tunerManager.reset()
    }
}
