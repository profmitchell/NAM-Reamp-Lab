//
//  AudioPluginManager.swift
//  NAM Reamp Lab
//
//  Created by Mitchell Cohen on 1/23/26.
//

@preconcurrency import AVFoundation
import AppKit
import Combine
import CoreAudioKit
import Foundation

/// Manages Audio Unit loading, state management and UI hosting
@MainActor
class AudioPluginManager: ObservableObject {
  static let shared = AudioPluginManager()

  @Published var loadedAudioUnits: [AVAudioUnit] = []
  @Published var effectNodes: [AVAudioUnit] = []

  private init() {}

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
    let components = manager.components(
      matching: AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: 0,
        componentManufacturer: 0,
        componentFlags: 0,
        componentFlagsMask: 0
      ))

    let namComponent = components.first { component in
      let name = component.name.lowercased()
      let manufacturer = component.manufacturerName.lowercased()

      if name.contains("neural amp modeler") || name.contains("neuralampmodeler") || name == "nam"
        || manufacturer.contains("steven atkinson") || manufacturer.contains("sdatkinson")
      {
        return true
      }
      return false
    }

    return namComponent
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

  /// Gets the Audio Unit view for a loaded effect
  func getAudioUnitViewController(at index: Int) async -> NSViewController? {
    guard index < effectNodes.count else { return nil }
    let avAudioUnit = effectNodes[index]

    return await withCheckedContinuation { continuation in
      // Add a timeout to requestViewController if possible, or just handle nil gracefully
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

  func clearEffects(engine: AVAudioEngine?) {
    for node in effectNodes {
      if let engine = engine {
        engine.disconnectNodeOutput(node)
        engine.detach(node)
      }
    }
    effectNodes.removeAll()
    loadedAudioUnits.removeAll()
  }

  func addEffectNode(_ audioUnit: AVAudioUnit, engine: AVAudioEngine?) {
    if let engine = engine {
      engine.attach(audioUnit)
    }
    effectNodes.append(audioUnit)
    loadedAudioUnits = effectNodes  // Keep in sync
  }

  /// Captures the current state and preset names of all loaded Audio Units
  func capturePluginStates() -> [Int: (data: Data?, presetName: String?)] {
    var states: [Int: (data: Data?, presetName: String?)] = [:]

    for (index, unit) in effectNodes.enumerated() {
      var presetName: String?
      var capturedData: Data?

      // 1. Capture preset name
      if unit.auAudioUnit.componentDescription.componentManufacturer == FourCharCode("SdAk") {
        // NAM - extract from state or current file
        if let fullState = unit.auAudioUnit.fullState,
          let path = (fullState["modelPath"] as? String) ?? (fullState["NAMModelPath"] as? String)
        {
          presetName = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        }
      } else {
        // Standard AU
        presetName = unit.auAudioUnit.currentPreset?.name
      }

      // 2. Capture full state data
      if let fullState = unit.auAudioUnit.fullState {
        do {
          capturedData = try NSKeyedArchiver.archivedData(
            withRootObject: fullState, requiringSecureCoding: false)
        } catch {
          print("Failed to capture state for plugin \(index): \(error)")
        }
      }

      states[index] = (data: capturedData, presetName: presetName)
    }

    return states
  }

  /// Restores state to a loaded Audio Unit
  func restorePluginState(at index: Int, from data: Data) {
    guard index < effectNodes.count else { return }
    let audioUnit = effectNodes[index]

    do {
      if let state = try NSKeyedUnarchiver.unarchivedObject(
        ofClasses: [NSDictionary.self, NSString.self, NSNumber.self, NSData.self, NSArray.self],
        from: data) as? [String: Any]
      {
        audioUnit.auAudioUnit.fullState = state
      }
    } catch {
      print("Error restoring plugin state: \(error)")
    }
  }
}
