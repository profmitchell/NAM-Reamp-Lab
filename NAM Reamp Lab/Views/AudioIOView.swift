//
//  AudioIOView.swift
//  NAM Reamp Lab
//
//  Created by Mitchell Cohen on 1/22/26.
//

import SwiftUI
import AVFoundation
import CoreAudioKit
import AppKit

/// Audio Input/Output configuration and monitoring view
struct AudioIOView: View {
    @StateObject private var audioEngine = AudioEngine.shared
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Top toolbar with transport controls
            transportBar
            
            Divider()
            
            // Main content
            HStack(spacing: 0) {
                // Left: Device selection
                devicePanel
                    .frame(width: 280)
                
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
        .frame(height: 180)
        .background(Color(NSColor.controlBackgroundColor))
        .alert("Audio Error", isPresented: $showingError) {
            Button("OK") { }
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
            // Play/Stop button
            Button {
                toggleEngine()
            } label: {
                Image(systemName: audioEngine.isRunning ? "stop.fill" : "play.fill")
                    .font(.title2)
                    .foregroundColor(audioEngine.isRunning ? .red : .green)
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
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
            
            // Monitoring toggle
            Toggle(isOn: $audioEngine.isMonitoring) {
                Label("Monitor", systemImage: "headphones")
            }
            .toggleStyle(.button)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    // MARK: - Device Panel
    
    private var devicePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Audio Devices")
                .font(.headline)
                .foregroundColor(.secondary)
            
            // Input device
            VStack(alignment: .leading, spacing: 4) {
                Label("Input", systemImage: "mic")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("Input", selection: $audioEngine.selectedInputDevice) {
                    Text("None").tag(nil as AudioDeviceInfo?)
                    ForEach(audioEngine.inputDevices) { device in
                        Text(device.name).tag(device as AudioDeviceInfo?)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            
            // Output device
            VStack(alignment: .leading, spacing: 4) {
                Label("Output", systemImage: "speaker.wave.2")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Picker("Output", selection: $audioEngine.selectedOutputDevice) {
                    Text("None").tag(nil as AudioDeviceInfo?)
                    ForEach(audioEngine.outputDevices) { device in
                        Text(device.name).tag(device as AudioDeviceInfo?)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            
            // Refresh button
            Button {
                audioEngine.refreshDevices()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Meters Panel
    
    private var metersPanel: some View {
        HStack(spacing: 24) {
            // Input meter
            VStack(spacing: 8) {
                LevelMeter(level: audioEngine.inputLevel, label: "IN")
                
                // Input gain
                VStack(spacing: 2) {
                    Text("Gain")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Slider(value: $audioEngine.inputGain, in: 0...2)
                        .frame(width: 60)
                    Text("\(Int(audioEngine.inputGain * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            // Output meter
            VStack(spacing: 8) {
                LevelMeter(level: audioEngine.outputLevel, label: "OUT")
                
                // Output gain
                VStack(spacing: 2) {
                    Text("Gain")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Slider(value: $audioEngine.outputGain, in: 0...2)
                        .frame(width: 60)
                    Text("\(Int(audioEngine.outputGain * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
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
            do {
                try audioEngine.start()
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
}

// MARK: - Level Meter

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

// MARK: - Plugin UI Host View

struct PluginUIHostView: View {
    let audioUnit: AVAudioUnit
    let name: String
    
    @State private var viewController: NSViewController?
    @State private var isLoading = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(name)
                    .font(.headline)
                Spacer()
                Button {
                    // Close or minimize
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
            }
            .padding(8)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Plugin UI
            if isLoading {
                ProgressView("Loading plugin UI...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let vc = viewController {
                AudioUnitViewRepresentable(viewController: vc)
            } else {
                VStack {
                    Image(systemName: "rectangle.dashed")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No UI available")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .task {
            await loadPluginUI()
        }
    }
    
    private func loadPluginUI() async {
        // Request the Audio Unit's custom view controller
        // Note: requestViewController is an extension on AUAudioUnit
        viewController = await withCheckedContinuation { continuation in
            audioUnit.auAudioUnit.requestViewController { vc in
                if let vc = vc {
                    continuation.resume(returning: vc)
                } else {
                    // Fallback: Create a generic AU view
                    DispatchQueue.main.async {
                        let auView = AUGenericView(audioUnit: audioUnit.audioUnit)
                        auView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
                        let vc = NSViewController()
                        vc.view = auView
                        continuation.resume(returning: vc)
                    }
                }
            }
        }
        
        // Defer state update to avoid publishing during view update
        await MainActor.run {
            isLoading = false
        }
    }
}

// MARK: - NSViewControllerRepresentable for Audio Unit View

struct AudioUnitViewRepresentable: NSViewControllerRepresentable {
    let viewController: NSViewController
    
    func makeNSViewController(context: Context) -> NSViewController {
        return viewController
    }
    
    func updateNSViewController(_ nsViewController: NSViewController, context: Context) {
        // No updates needed
    }
}

// MARK: - Preview

#Preview {
    AudioIOView()
        .frame(width: 800)
}
