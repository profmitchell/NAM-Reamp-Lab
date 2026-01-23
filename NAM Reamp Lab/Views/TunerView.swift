//
//  TunerView.swift
//  NAM Reamp Lab
//
//  Created by Mitchell Cohen on 1/23/26.
//

import SwiftUI

struct TunerView: View {
    @StateObject private var audioEngine = AudioEngine.shared
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Guitar Tuner")
                .font(.headline)
            
            HStack {
                Text(audioEngine.tunerNote)
                    .font(.system(size: 80, weight: .bold, design: .monospaced))
                    .foregroundColor(abs(audioEngine.tunerCentsOff) < 5 ? .green : .primary)
                
                VStack(alignment: .leading) {
                    Text(String(format: "%.1f Hz", audioEngine.tunerFrequency))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(String(format: "%+.1f cents", audioEngine.tunerCentsOff))
                        .font(.caption)
                        .foregroundColor(abs(audioEngine.tunerCentsOff) < 5 ? .green : .orange)
                }
            }
            
            // Cents Meter
            ZStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 10)
                    .cornerRadius(5)
                
                // Center line
                Rectangle()
                    .fill(Color.secondary)
                    .frame(width: 2, height: 20)
                
                // Indicator
                Circle()
                    .fill(abs(audioEngine.tunerCentsOff) < 5 ? Color.green : Color.orange)
                    .frame(width: 15, height: 15)
                    .offset(x: CGFloat(clamp(audioEngine.tunerCentsOff, min: -50, max: 50)) * 2)
            }
            .frame(width: 200)
            .padding(.horizontal)
            
            HStack {
                Text("-50")
                Spacer()
                Text("0")
                Spacer()
                Text("+50")
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(.secondary)
            .frame(width: 200)
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.min(Swift.max(value, min), max)
    }
}

#Preview {
    TunerView()
        .frame(width: 300, height: 250)
}
