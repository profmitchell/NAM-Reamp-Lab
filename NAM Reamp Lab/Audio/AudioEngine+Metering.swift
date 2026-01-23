//
//  AudioEngine+Metering.swift
//  NAM Reamp Lab
//

import Foundation
import AVFoundation
import Accelerate

extension AudioEngine {
    
    /// Installs audio taps on input and output for real RMS level metering
    func installLevelMetering() {
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
    nonisolated func calculateRMSLevel(buffer: AVAudioPCMBuffer) -> Float {
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
    func removeLevelMetering() {
        inputNode?.removeTap(onBus: 0)
        mainMixerNode?.removeTap(onBus: 0)
        inputLevelRMS = 0
        outputLevelRMS = 0
    }
    
    func startLevelMetering() {
        installLevelMetering()
    }
    
    func stopLevelMetering() {
        removeLevelMetering()
        inputLevel = 0
        outputLevel = 0
    }
}
