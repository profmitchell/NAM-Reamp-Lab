//
//  LevelMeter.swift
//  NAM Reamp Lab
//

import SwiftUI

struct LevelMeter: View {
    let level: Float
    let label: String
    
    private let meterHeight: CGFloat = 80
    private let meterWidth: CGFloat = 24
    
    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            ZStack(alignment: .bottom) {
                // Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.3))
                    .frame(width: meterWidth, height: meterHeight)
                
                // Level
                RoundedRectangle(cornerRadius: 4)
                    .fill(levelGradient)
                    .frame(width: meterWidth - 4, height: max(0, CGFloat(level) * (meterHeight - 4)))
                    .padding(2)
                
                // Peak markers
                ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { marker in
                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: meterWidth, height: 1)
                        .offset(y: -CGFloat(marker) * meterHeight + meterHeight / 2)
                }
            }
            
            // dB label
            Text(dbString)
                .font(.caption2)
                .monospacedDigit()
                .foregroundColor(.secondary)
        }
    }
    
    private var levelGradient: LinearGradient {
        LinearGradient(
            colors: [.green, .yellow, .orange, .red],
            startPoint: .bottom,
            endPoint: .top
        )
    }
    
    private var dbString: String {
        if level <= 0 {
            return "-∞"
        }
        let db = 20 * log10(level)
        return String(format: "%.0f", db)
    }
}
