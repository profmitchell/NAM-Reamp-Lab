//
//  AudioEngine+Devices.swift
//  NAM Reamp Lab
//

import Foundation
import AVFoundation

#if os(macOS)
import CoreAudio
#endif

extension AudioEngine {
    
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
    
    func configureDevices() throws {
        #if os(macOS)
        guard let engine = engine else { return }
        
        // Set the input device on the AVAudioEngine directly if a specific device is selected
        if let inputDevice = selectedInputDevice {
            try setAudioUnitDevice(engine.inputNode.audioUnit!, deviceID: inputDevice.id, isInput: true)
        }
        
        // For output, AVAudioEngine uses the system default output automatically
        if let outputDevice = selectedOutputDevice {
            try setAudioUnitDevice(engine.outputNode.audioUnit!, deviceID: outputDevice.id, isInput: false)
        }
        #endif
    }
    
    #if os(macOS)
    /// Sets the audio device directly on an AudioUnit (the proper way for AVAudioEngine)
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
        
        print("Set \(isInput ? "input" : "output") device to ID: \(deviceID)")
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
    #endif
    
    func getAudioDevices(isInput: Bool) -> [AudioDeviceInfo] {
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
    func getDeviceInfo(deviceID: AudioDeviceID, checkInput: Bool) -> AudioDeviceInfo? {
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
            sampleRate: 48000,
            channelCount: checkInput ? inputChannelCount : outputChannelCount
        )
    }
    #endif
}
