//
//  AudioDeviceManager.swift
//  NAM Reamp Lab
//
//  Created by Mitchell Cohen on 1/23/26.
//

import AVFoundation
import Combine
import Foundation

#if os(macOS)
  import CoreAudio
#endif

/// Manages audio device discovery and selection
@MainActor
class AudioDeviceManager: ObservableObject {
  static let shared = AudioDeviceManager()

  @Published var inputDevices: [AudioDeviceInfo] = []
  @Published var outputDevices: [AudioDeviceInfo] = []
  @Published var selectedInputDevice: AudioDeviceInfo?
  @Published var selectedOutputDevice: AudioDeviceInfo?

  private init() {
    refreshDevices()
  }

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
  }

  #if os(macOS)
    /// Configures the selected devices on the system and potentially on an AVAudioEngine
  func configureDevices(for engine: AVAudioEngine?) throws {
      refreshDevices()
      normalizeSelectedDevices()

      let inputID = selectedInputDevice?.id
      let outputID = selectedOutputDevice?.id

      print("🎸 configureDevices starting - InputID: \(inputID ?? 0), OutputID: \(outputID ?? 0)")

      // On macOS, AVAudioEngine doesn't support using different devices for input and output
      // directly if they are separate hardware objects.
      // The most reliable way is to set the system default input/output and let the engine follow.
      // We do this BEFORE trying to set it on the AudioUnit.

      if let iID = inputID, iID != 0 {
        do {
          try setInputDevice(iID)
          print("✅ System input device set to \(iID)")
        } catch {
          print("⚠️ Failed to set system input device: \(error)")
        }
      }

      if let oID = outputID, oID != 0 {
        do {
          try setOutputDevice(oID)
          print("✅ System output device set to \(oID)")
        } catch {
          print("⚠️ Failed to set system output device: \(error)")
        }
      }

      // Secondary: Try to set it on the engine's nodes if they're available
      if let engine = engine {
        if let iID = inputID, iID != 0 {
          do {
            try setAudioUnitDevice(engine.inputNode.audioUnit!, deviceID: iID, isInput: true)
            print("✅ Input node device ID set to \(iID)")
          } catch {
            print(
              "ℹ️ Note: Could not set device \(iID) on inputNode directly (this is often normal during transition)"
            )
          }
        }

        if let oID = outputID, oID != 0 {
          do {
            try setAudioUnitDevice(engine.outputNode.audioUnit!, deviceID: oID, isInput: false)
            print("✅ Output node device ID set to \(oID)")
          } catch {
            print("ℹ️ Note: Could not set device \(oID) on outputNode directly")
          }
        }
      }
    }

    private func normalizeSelectedDevices() {
      if let resolvedInput = resolveDeviceSelection(
        current: selectedInputDevice,
        devices: inputDevices,
        defaultID: getDefaultInputDeviceID()
      ) {
        if resolvedInput != selectedInputDevice {
          selectedInputDevice = resolvedInput
        }
      } else {
        selectedInputDevice = nil
      }

      if let resolvedOutput = resolveDeviceSelection(
        current: selectedOutputDevice,
        devices: outputDevices,
        defaultID: getDefaultOutputDeviceID()
      ) {
        if resolvedOutput != selectedOutputDevice {
          selectedOutputDevice = resolvedOutput
        }
      } else {
        selectedOutputDevice = nil
      }
    }

    private func resolveDeviceSelection(
      current: AudioDeviceInfo?,
      devices: [AudioDeviceInfo],
      defaultID: AudioDeviceID?
    ) -> AudioDeviceInfo? {
      if let current = current {
        if let match = devices.first(where: { $0.id == current.id }) {
          return match
        }
        if let match = devices.first(where: { $0.uid == current.uid }) {
          return match
        }
      }

      if let defaultID = defaultID,
         let match = devices.first(where: { $0.id == defaultID }) {
        return match
      }

      return devices.first
    }

    /// Sets the audio device directly on an AudioUnit
    func setAudioUnitDevice(_ audioUnit: AudioUnit, deviceID: AudioDeviceID, isInput: Bool) throws {
      var deviceID = deviceID
      let propertyID = kAudioOutputUnitProperty_CurrentDevice

      let status = AudioUnitSetProperty(
        audioUnit,
        propertyID,
        kAudioUnitScope_Global,
        0,
        &deviceID,
        UInt32(MemoryLayout<AudioDeviceID>.size)
      )

      if status != noErr {
        print("Failed to set audio device (status: \(status))")
        throw AudioEngineError.deviceConfigurationFailed
      }
    }

    func setInputDevice(_ deviceID: AudioDeviceID) throws {
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

    func setOutputDevice(_ deviceID: AudioDeviceID) throws {
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

    func getDefaultInputDeviceID() -> AudioDeviceID? {
      var deviceID = AudioDeviceID(0)
      var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
      var propertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
      )

      let status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &propertyAddress,
        0,
        nil,
        &dataSize,
        &deviceID
      )

      return status == noErr && deviceID != 0 ? deviceID : nil
    }

    func getDefaultOutputDeviceID() -> AudioDeviceID? {
      var deviceID = AudioDeviceID(0)
      var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
      var propertyAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
      )

      let status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &propertyAddress,
        0,
        nil,
        &dataSize,
        &deviceID
      )

      return status == noErr && deviceID != 0 ? deviceID : nil
    }

    func getAudioDevices(isInput: Bool) -> [AudioDeviceInfo] {
      var devices: [AudioDeviceInfo] = []

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

      return devices
    }

    func getDeviceInfo(deviceID: AudioDeviceID, checkInput: Bool) -> AudioDeviceInfo? {
      guard deviceID != 0 else { return nil }

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

      if status != noErr {
        print("⚠️ Failed to get device name for ID: \(deviceID) (status: \(status))")
      }

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

      if status != noErr {
        print("⚠️ Failed to get device UID for ID: \(deviceID) (status: \(status))")
      }

      // Get nominal sample rate
      propertyAddress.mSelector = kAudioDevicePropertyNominalSampleRate
      var nominalSampleRate: Float64 = 0
      dataSize = UInt32(MemoryLayout<Float64>.size)

      status = AudioObjectGetPropertyData(
        deviceID, &propertyAddress, 0, nil, &dataSize, &nominalSampleRate)
      if status != noErr {
        print("⚠️ Failed to get sample rate for ID: \(deviceID), defaulting to 48000")
        nominalSampleRate = 48000
      }

      // Check channel counts
      func countChannels(scope: AudioObjectPropertyScope) -> Int {
        var addr = AudioObjectPropertyAddress(
          mSelector: kAudioDevicePropertyStreamConfiguration,
          mScope: scope,
          mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0
        let res = AudioObjectGetPropertyDataSize(deviceID, &addr, 0, nil, &size)
        guard res == noErr && size > 0 else { return 0 }

        let bufferListSize = Int(size)
        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: bufferListSize)
        defer { bufferList.deallocate() }

        let res2 = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, bufferList)
        guard res2 == noErr else { return 0 }

        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        var totalChannels = 0
        for buffer in buffers {
          totalChannels += Int(buffer.mNumberChannels)
        }
        return totalChannels
      }

      let inputChannelCount = countChannels(scope: kAudioDevicePropertyScopeInput)
      let outputChannelCount = countChannels(scope: kAudioDevicePropertyScopeOutput)

      return AudioDeviceInfo(
        id: deviceID,
        name: (name as String?) ?? "Unknown Device",
        uid: (uid as String?) ?? UUID().uuidString,
        isInput: inputChannelCount > 0,
        isOutput: outputChannelCount > 0,
        sampleRate: nominalSampleRate,
        channelCount: checkInput ? inputChannelCount : outputChannelCount
      )
    }
  #else
    func getAudioDevices(isInput: Bool) -> [AudioDeviceInfo] { return [] }
  #endif
}
