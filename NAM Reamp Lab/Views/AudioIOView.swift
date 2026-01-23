//
//  AudioIOView.swift
//  NAM Reamp Lab
//
//  Created by Mitchell Cohen on 1/22/26.
//

import AVFoundation
import AppKit
import CoreAudioKit
import SwiftUI

/// Audio Input/Output configuration and monitoring view
struct AudioIOView: View {
  @StateObject private var audioEngine = AudioEngine.shared
  @State private var showingError = false
  @State private var errorMessage = ""

  var body: some View {
    VStack(spacing: 0) {
      // Main content - everything in one row
      HStack(spacing: 0) {
        // Left: START button and Device selection
        devicePanel
          .frame(width: 300)

        Divider()

        // Center: Level meters
        metersPanel
          .frame(minWidth: 200)

        Divider()

        // Right: Chain status
        chainPanel
          .frame(width: 280)
      }
    }
    .frame(height: 200)
    .background(Color(NSColor.controlBackgroundColor))
    .alert("Audio Error", isPresented: $showingError) {
      Button("OK") {}
    } message: {
      Text(errorMessage)
    }
    .onAppear {
      audioEngine.refreshDevices()
    }
  }

  // MARK: - Transport Bar

  private var transportBar: some View {
    HStack(spacing: 16) {
      // PROMINENT Play/Stop button
      Button {
        toggleEngine()
      } label: {
        HStack(spacing: 8) {
          Image(systemName: audioEngine.isRunning ? "stop.fill" : "play.fill")
            .font(.title2)
          Text(audioEngine.isRunning ? "STOP" : "START")
            .fontWeight(.bold)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(audioEngine.isRunning ? Color.red : Color.green)
        .cornerRadius(8)
      }
      .buttonStyle(.plain)
      .help(audioEngine.isRunning ? "Stop Audio Engine" : "Start Audio Engine")

      // Status indicator
      HStack(spacing: 8) {
        Circle()
          .fill(audioEngine.isRunning ? Color.green : Color.gray)
          .frame(width: 10, height: 10)
        Text(audioEngine.isRunning ? "Running" : "Stopped")
          .foregroundColor(.secondary)
      }

      Spacer()

      // Monitoring toggle - PROMINENT
      Toggle(isOn: $audioEngine.isMonitoring) {
        HStack {
          Image(systemName: audioEngine.isMonitoring ? "speaker.wave.2.fill" : "speaker.slash.fill")
          Text(audioEngine.isMonitoring ? "Monitor" : "Monitor")
        }
      }
      .toggleStyle(.button)
      .tint(audioEngine.isMonitoring ? .blue : .gray)

      // Tuner toggle
      Toggle(isOn: $audioEngine.isTunerActive) {
        HStack {
          Image(systemName: "tuningfork")
          Text("Tuner")
        }
      }
      .toggleStyle(.button)
      .tint(audioEngine.isTunerActive ? .purple : .gray)

      Divider()
        .frame(height: 24)

      // Buffer size
      HStack {
        Text("Buffer:")
          .foregroundColor(.secondary)
        Picker("", selection: $audioEngine.bufferSize) {
          Text("64").tag(64)
          Text("128").tag(128)
          Text("256").tag(256)
          Text("512").tag(512)
          Text("1024").tag(1024)
        }
        .pickerStyle(.menu)
        .frame(width: 80)
      }

      // Sample rate
      HStack {
        Text("Rate:")
          .foregroundColor(.secondary)
        Picker("", selection: $audioEngine.sampleRate) {
          Text("44.1k").tag(44100.0)
          Text("48k").tag(48000.0)
          Text("96k").tag(96000.0)
        }
        .pickerStyle(.menu)
        .frame(width: 80)
      }
    }
    .padding(.horizontal)
    .padding(.vertical, 8)
  }

  // MARK: - Device Panel

  private var devicePanel: some View {
    VStack(alignment: .leading, spacing: 10) {
      // BIG START BUTTON AT TOP
      Button {
        toggleEngine()
      } label: {
        HStack {
          Image(systemName: audioEngine.isRunning ? "stop.fill" : "play.fill")
            .font(.title2)
          Text(audioEngine.isRunning ? "STOP ENGINE" : "START ENGINE")
            .fontWeight(.bold)
          Spacer()
          Circle()
            .fill(audioEngine.isRunning ? Color.green : Color.gray)
            .frame(width: 12, height: 12)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(audioEngine.isRunning ? Color.red : Color.green)
        .cornerRadius(8)
      }
      .buttonStyle(.plain)

      // Monitor toggle
      Toggle(isOn: $audioEngine.isMonitoring) {
        Label(
          audioEngine.isMonitoring ? "Monitoring ON" : "Monitoring OFF",
          systemImage: audioEngine.isMonitoring ? "speaker.wave.2.fill" : "speaker.slash")
      }
      .toggleStyle(.switch)
      .tint(.blue)

      Divider()

      // Input device
      HStack {
        Label("Input", systemImage: "mic")
          .font(.caption)
          .foregroundColor(.secondary)
          .frame(width: 60, alignment: .leading)

        Picker("", selection: $audioEngine.selectedInputDevice) {
          Text("None").tag(nil as AudioDeviceInfo?)
          ForEach(audioEngine.inputDevices) { device in
            Text(device.name).tag(device as AudioDeviceInfo?)
          }
        }
        .pickerStyle(.menu)
        .labelsHidden()
      }

      // Input channel selection
      if audioEngine.selectedInputDevice != nil {
        HStack {
          Label("Channel", systemImage: "arrow.right.to.line.alt")
            .font(.caption)
            .foregroundColor(.secondary)
            .frame(width: 60, alignment: .leading)

          Picker("", selection: $audioEngine.inputChannelIndex) {
            ForEach(0..<audioEngine.availableInputChannels.count, id: \.self) { index in
              Text(audioEngine.availableInputChannels[index]).tag(index)
            }
          }
          .pickerStyle(.menu)
          .labelsHidden()
        }
      }

      // Output device
      HStack {
        Label("Output", systemImage: "speaker.wave.2")
          .font(.caption)
          .foregroundColor(.secondary)
          .frame(width: 60, alignment: .leading)

        Picker("", selection: $audioEngine.selectedOutputDevice) {
          Text("None").tag(nil as AudioDeviceInfo?)
          ForEach(audioEngine.outputDevices) { device in
            Text(device.name).tag(device as AudioDeviceInfo?)
          }
        }
        .pickerStyle(.menu)
        .labelsHidden()
      }

      Spacer()
    }
    .padding()
  }

  // MARK: - Meters Panel

  private var metersPanel: some View {
    VStack(spacing: 12) {
      if audioEngine.isTunerActive {
        TunerView()
          .frame(height: 140)
      } else {
        HStack(spacing: 20) {
          LevelMeter(level: audioEngine.inputLevel, label: "INPUT")
          LevelMeter(level: audioEngine.outputLevel, label: "OUTPUT")
        }
      }
    }
    .padding()
  }

  // MARK: - Chain Panel

  private var chainPanel: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Active Chain")
        .font(.headline)
        .foregroundColor(.secondary)

      if let chain = audioEngine.currentChain {
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Image(systemName: "link")
              .foregroundColor(.accentColor)
            Text(chain.name)
              .fontWeight(.medium)
          }

          Text("\(audioEngine.loadedAudioUnits.count) plugins loaded")
            .font(.caption)
            .foregroundColor(.secondary)

          // Plugin list
          ScrollView {
            VStack(alignment: .leading, spacing: 4) {
              ForEach(Array(chain.plugins.enumerated()), id: \.element.id) { index, plugin in
                HStack(spacing: 6) {
                  Circle()
                    .fill(plugin.isBypassed ? Color.orange : Color.green)
                    .frame(width: 6, height: 6)
                  Text(plugin.name)
                    .font(.caption)
                    .lineLimit(1)
                }
              }
            }
          }
          .frame(maxHeight: 60)
        }
      } else {
        VStack(spacing: 8) {
          Image(systemName: "link.badge.plus")
            .font(.title2)
            .foregroundColor(.secondary)
          Text("No chain loaded")
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }

      Spacer()
    }
    .padding()
  }

  // MARK: - Actions

  private func toggleEngine() {
    if audioEngine.isRunning {
      audioEngine.stop()
    } else {
      Task {
        do {
          try await audioEngine.start()
        } catch {
          errorMessage = error.localizedDescription
          showingError = true
        }
      }
    }
  }
}

// MARK: - Preview

#Preview {
  AudioIOView()
    .frame(width: 800)
}
