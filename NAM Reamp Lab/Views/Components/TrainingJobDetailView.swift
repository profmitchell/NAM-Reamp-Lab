//
//  TrainingJobDetailView.swift
//  NAM Reamp Lab
//

import AppKit
import SwiftUI

struct TrainingJobDetailView: View {
  let job: TrainingJob

  var body: some View {
    VStack(spacing: 0) {
      // Header
      jobHeader

      Divider()

      // Stats grid
      statsGrid

      Divider()

      // Log output
      logView
    }
  }

  private var jobHeader: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(job.displayName)
          .font(.title2)
          .fontWeight(.semibold)

        Spacer()

        statusBadge
      }

      if let error = job.errorMessage {
        Text(error)
          .foregroundColor(.red)
          .font(.caption)
      }
    }
    .padding()
  }

  private var statusBadge: some View {
    HStack(spacing: 4) {
      Image(systemName: job.status.icon)
      Text(job.status.rawValue)
    }
    .font(.caption)
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(statusBackgroundColor)
    .foregroundColor(statusForegroundColor)
    .cornerRadius(6)
  }

  private var statusBackgroundColor: Color {
    switch job.status {
    case .pending: return Color.secondary.opacity(0.2)
    case .running: return Color.blue.opacity(0.2)
    case .completed: return Color.green.opacity(0.2)
    case .failed: return Color.red.opacity(0.2)
    case .cancelled: return Color.orange.opacity(0.2)
    }
  }

  private var statusForegroundColor: Color {
    switch job.status {
    case .pending: return .secondary
    case .running: return .blue
    case .completed: return .green
    case .failed: return .red
    case .cancelled: return .orange
    }
  }

  private var statsGrid: some View {
    LazyVGrid(
      columns: [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
      ], spacing: 16
    ) {
      StatView(title: "Epoch", value: "\(job.currentEpoch)/\(job.parameters.epochs)")
      StatView(title: "Progress", value: "\(Int(job.progress * 100))%")
      ESRStatView(title: "ESR", value: job.currentLoss)
      StatView(title: "Duration", value: job.formattedDuration ?? "-")
    }
    .padding()
  }

  private var logView: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Training Log")
          .font(.headline)
          .foregroundColor(.secondary)

        Spacer()

        Button {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(job.logOutput, forType: .string)
        } label: {
          Label("Copy", systemImage: "doc.on.doc")
            .font(.caption)
        }
        .buttonStyle(.borderless)
        .disabled(job.logOutput.isEmpty)
      }

      ScrollView {
        ScrollViewReader { proxy in
          Text(job.logOutput.isEmpty ? "No output yet..." : job.logOutput)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)  // Make text selectable
            .frame(maxWidth: .infinity, alignment: .leading)
            .id("logBottom")
            .onChange(of: job.logOutput) { _, _ in
              withAnimation {
                proxy.scrollTo("logBottom", anchor: .bottom)
              }
            }
        }
      }
      .padding(8)
      .background(Color(NSColor.textBackgroundColor))
      .cornerRadius(6)
    }
    .padding()
  }
}

// MARK: - Stat View

struct StatView: View {
  let title: String
  let value: String

  var body: some View {
    VStack(spacing: 4) {
      Text(value)
        .font(.title3)
        .fontWeight(.semibold)
        .monospacedDigit()

      Text(title)
        .font(.caption)
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 8)
    .background(Color(NSColor.controlBackgroundColor))
    .cornerRadius(8)
  }
}

// MARK: - ESR Stat View (with color coding)

struct ESRStatView: View {
  let title: String
  let value: Double?

  var body: some View {
    VStack(spacing: 4) {
      if let esr = value {
        Text(String(format: "%.4f", esr))
          .font(.title3)
          .fontWeight(.semibold)
          .foregroundColor(esrColor(esr))
          .monospacedDigit()
      } else {
        Text("-")
          .font(.title3)
          .fontWeight(.semibold)
          .foregroundColor(.secondary)
      }

      HStack(spacing: 4) {
        Text(title)
          .font(.caption)
          .foregroundColor(.secondary)

        if let esr = value {
          Text("(\(esrQuality(esr)))")
            .font(.caption)
            .foregroundColor(esrColor(esr))
        }
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 8)
    .background(Color(NSColor.controlBackgroundColor))
    .cornerRadius(8)
  }

  /// Returns color based on ESR value (lower is better)
  private func esrColor(_ esr: Double) -> Color {
    if esr < 0.01 { return .green }  // Excellent: < 1%
    if esr < 0.02 { return .mint }  // Great: 1-2%
    if esr < 0.05 { return .blue }  // Good: 2-5%
    if esr < 0.10 { return .orange }  // Fair: 5-10%
    return .red  // Poor: > 10%
  }

  /// Returns quality description based on ESR
  private func esrQuality(_ esr: Double) -> String {
    if esr < 0.01 { return "Excellent" }
    if esr < 0.02 { return "Great" }
    if esr < 0.05 { return "Good" }
    if esr < 0.10 { return "Fair" }
    return "Training..."
  }
}
