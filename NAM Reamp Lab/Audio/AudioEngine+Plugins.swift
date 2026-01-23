//
//  AudioEngine+Plugins.swift
//  NAM Reamp Lab
//

@preconcurrency import AVFoundation
import AppKit
import CoreAudioKit
import Foundation

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
        if let namUnit = try await AudioPluginManager.shared.loadNAMAudioUnit() {
          if let modelPath = plugin.path {
            try await AudioPluginManager.shared.loadNAMModel(namUnit, modelPath: modelPath)
          }
          // Restore saved state if available (includes NAM model path)
          if let presetData = plugin.presetData {
            AudioPluginManager.shared.restorePluginState(at: loadedPluginIndex, from: presetData)
          }
          addEffectNode(namUnit)
          loadedPluginIndex += 1
        }

      case .audioUnit:
        // Load the specified Audio Unit
        if let desc = plugin.componentDescription {
          let unit = try await AudioPluginManager.shared.loadAudioUnit(
            desc.toAudioComponentDescription())
          addEffectNode(unit)
          // Restore saved preset state (includes all plugin settings)
          if let presetData = plugin.presetData {
            AudioPluginManager.shared.restorePluginState(at: loadedPluginIndex, from: presetData)
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
    try? await Task.sleep(for: .milliseconds(50))
    try rebuildAudioChain()

    // Restart if was running
    if wasRunning {
      try await start()
    }
  }

  /// Updates the current chain with captured plugin states
  func updateChainWithPluginStates() -> ProcessingChain? {
    guard var chain = currentChain else { return nil }

    let states = AudioPluginManager.shared.capturePluginStates()

    // Map states back to plugins
    var pluginIndex = 0
    for i in 0..<chain.plugins.count {
      if chain.plugins[i].isEnabled && !chain.plugins[i].isBypassed {
        if let stateData = states[pluginIndex] {
          chain.plugins[i].presetData = stateData
        }
        pluginIndex += 1
      }
    }

    currentChain = chain
    return chain
  }

  /// Clears all effects from the chain
  func clearEffects() {
    AudioPluginManager.shared.clearEffects(engine: engine)
    currentChain = nil
  }

  /// Gets the Audio Unit view for a loaded effect
  func getAudioUnitViewController(at index: Int) async -> NSViewController? {
    return await AudioPluginManager.shared.getAudioUnitViewController(at: index)
  }

  func rebuildAudioChain() throws {
    guard let engine = engine,
      let inputNode = inputNode,
      let mixer = mainMixerNode,
      let inputSelector = inputSelectorMixerNode
    else {
      throw AudioEngineError.engineNotInitialized
    }

    removeLevelMetering()

    let effectNodes = AudioPluginManager.shared.effectNodes

    // Disconnect everything first
    for effect in effectNodes {
      engine.disconnectNodeInput(effect)
      engine.disconnectNodeOutput(effect)
    }
    engine.disconnectNodeInput(inputSelector)
    engine.disconnectNodeOutput(inputSelector)
    for bus in 0..<mixer.numberOfInputs {
      engine.disconnectNodeInput(mixer, bus: bus)
    }

    // 1. INPUT STAGE: Hardware -> Input Selector
    // We use the node's output format directly to ensure compatibility.
    let hardwareFormat = inputNode.outputFormat(forBus: 0)
    let hasValidHardware = hardwareFormat.sampleRate > 0 && hardwareFormat.channelCount > 0

    if hasValidHardware {
      // CHANNEL SELECTION: Map one hardware channel to the engine
      // On macOS, we can use the channelMap property of the inputNode's auAudioUnit.
      // channelMap is an array of NSNumbers where the index is the output channel and
      // the value is the input (hardware) channel.

      // We map the selected hardware channel to output channel 0
      let map = [NSNumber(value: inputChannelIndex)]
      inputNode.auAudioUnit.channelMap = map
      print("🎸 Mapping hardware input channel \(inputChannelIndex + 1) to engine output 0")

      // Use a MONO format for the selection bridge to minimize processing
      let monoFormat = AVAudioFormat(
        standardFormatWithSampleRate: hardwareFormat.sampleRate, channels: 1)!

      // Connect Hardware to Selector Mixer
      engine.connect(inputNode, to: inputSelector, format: monoFormat)
      print("🎸 Connected mono input to selector mixer")
    }

    // 2. PROCESSING STAGE: Input Selector -> Effect Chain -> Main Mixer
    // We use a standardized processing format (Stereo) for all plugins.
    let standardRate = hardwareFormat.sampleRate > 0 ? hardwareFormat.sampleRate : sampleRate
    let processingFormat = AVAudioFormat(standardFormatWithSampleRate: standardRate, channels: 2)!

    // Determine the entry point for the effect chain
    var chainInputNode: AVAudioNode? = hasValidHardware ? inputSelector : nil

    if effectNodes.isEmpty {
      if let source = chainInputNode {
        engine.connect(source, to: mixer, format: processingFormat)
      }
    } else {
      var previousNode: AVAudioNode? = chainInputNode

      for effectNode in effectNodes {
        if let source = previousNode {
          engine.connect(source, to: effectNode, format: processingFormat)
        }
        previousNode = effectNode
      }

      if let lastNode = previousNode {
        engine.connect(lastNode, to: mixer, format: processingFormat)
      }
    }

    configureMainMixerConnection()
    updateGains()
    if hasValidHardware {
      installLevelMetering()
    }
  }

  func addEffectNode(_ audioUnit: AVAudioUnit) {
    AudioPluginManager.shared.addEffectNode(audioUnit, engine: engine)
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

    // Using Matrix Reverb as a placeholder for IR convolution in the live engine
    let reverbDescription = AudioComponentDescription(
      componentType: kAudioUnitType_Effect,
      componentSubType: kAudioUnitSubType_Reverb2,
      componentManufacturer: kAudioUnitManufacturer_Apple,
      componentFlags: 0,
      componentFlagsMask: 0
    )

    return try await AudioPluginManager.shared.loadAudioUnit(reverbDescription)
  }
}
