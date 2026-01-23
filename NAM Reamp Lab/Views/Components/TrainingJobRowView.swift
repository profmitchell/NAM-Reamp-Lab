//
//  TrainingJobRowView.swift
//  NAM Reamp Lab
//

import SwiftUI

struct TrainingJobRowView: View {
    let job: TrainingJob
    
    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            statusIcon
            
            // Job info
            VStack(alignment: .leading, spacing: 2) {
                Text(job.displayName)
                    .fontWeight(.medium)
                
                HStack(spacing: 8) {
                    Text(job.status.rawValue)
                        .font(.caption)
                        .foregroundColor(statusColor)
                    
                    if job.status == .running {
                        Text("Epoch \(job.currentEpoch)/\(job.totalEpochs)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let duration = job.formattedDuration {
                        Text(duration)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Progress or status indicator
            if job.status == .running {
                VStack(alignment: .trailing, spacing: 2) {
                    ProgressView(value: job.progress)
                        .frame(width: 80)
                    Text("\(Int(job.progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if let esr = job.currentLoss {
                HStack(spacing: 4) {
                    Text("ESR:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.4f", esr))
                        .font(.caption.bold())
                        .foregroundColor(esrColor(esr))
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private var statusIcon: some View {
        Group {
            switch job.status {
            case .pending:
                Image(systemName: "clock")
                    .foregroundColor(.secondary)
            case .running:
                ProgressView()
                    .scaleEffect(0.7)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            case .cancelled:
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.orange)
            }
        }
        .frame(width: 24)
    }
    
    private var statusColor: Color {
        switch job.status {
        case .pending: return .secondary
        case .running: return .blue
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .orange
        }
    }
    
    /// Returns color based on ESR value (lower is better)
    private func esrColor(_ esr: Double) -> Color {
        if esr < 0.01 { return .green }       // Excellent: < 1%
        if esr < 0.02 { return .mint }        // Great: 1-2%
        if esr < 0.05 { return .blue }        // Good: 2-5%
        if esr < 0.10 { return .orange }      // Fair: 5-10%
        return .red                            // Poor: > 10%
    }
}
