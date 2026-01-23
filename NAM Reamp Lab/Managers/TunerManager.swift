//
//  TunerManager.swift
//  NAM Reamp Lab
//

import Foundation
import AVFoundation
import Accelerate
import Combine

@MainActor
class TunerManager: ObservableObject {
    @Published var noteName: String = "--"
    @Published var centsOff: Double = 0
    @Published var frequency: Double = 0
    
    private let notes = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    
    func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        
        let frameLength = Int(buffer.frameLength)
        let sampleRate = buffer.format.sampleRate
        
        // Simple autocorrelation for pitch detection
        let pitch = detectPitch(data: channelData[0], length: frameLength, sampleRate: sampleRate)
        
        if pitch > 0 {
            let (note, cents) = frequencyToNote(pitch)
            DispatchQueue.main.async {
                self.frequency = pitch
                self.noteName = note
                self.centsOff = cents
            }
        }
    }
    
    private func detectPitch(data: UnsafePointer<Float>, length: Int, sampleRate: Double) -> Double {
        // Simple YIN or Autocorrelation approach
        // To keep it simple but functional for guitar:
        var maxCorr: Float = 0
        var maxLag = 0
        
        let minFreq = 60.0  // Low E
        let maxFreq = 1200.0 // High frets
        
        let minLag = Int(sampleRate / maxFreq)
        let maxLagVal = Int(sampleRate / minFreq)
        
        for lag in minLag...maxLagVal {
            var corr: Float = 0
            vDSP_dotpr(data, 1, data + lag, 1, &corr, vDSP_Length(length - lag))
            
            if corr > maxCorr {
                maxCorr = corr
                maxLag = lag
            }
        }
        
        if maxLag > 0 {
            return sampleRate / Double(maxLag)
        }
        
        return 0
    }
    
    private func frequencyToNote(_ freq: Double) -> (String, Double) {
        let a4 = 440.0
        let h = 12.0 * log2(freq / a4) + 69.0
        let noteNum = Int(round(h))
        let cents = 100.0 * (h - Double(noteNum))
        
        let noteName = notes[max(0, noteNum % 12)]
        let octave = (noteNum / 12) - 1
        
        return ("\(noteName)\(octave)", cents)
    }
    
    func reset() {
        noteName = "--"
        centsOff = 0
        frequency = 0
    }
}
