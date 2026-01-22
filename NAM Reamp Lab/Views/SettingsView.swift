//
//  SettingsView.swift
//  NAM Reamp Lab
//
//  Created by Mitchell Cohen on 1/22/26.
//

import SwiftUI
import UniformTypeIdentifiers

/// Main view for Tab 3 - Settings
struct SettingsView: View {
    @StateObject private var settings = AppSettings.shared
    @StateObject private var pythonManager = PythonManager.shared
    @StateObject private var audioUnitManager = AudioUnitHostManager.shared
    
    @State private var showingPythonPathPicker = false
    @State private var showingNAMPathPicker = false
    @State private var showingOutputFolderPicker = false
    @State private var showingModelFolderPicker = false
    @State private var showingIRFolderPicker = false
    @State private var isPythonTesting = false
    @State private var pythonTestResult: String?
    
    var body: some View {
        Form {
            // Python Configuration
            pythonSection
            
            // Folder Settings
            folderSection
            
            // Training Defaults
            trainingDefaultsSection
            
            // Audio Units
            audioUnitsSection
            
            // App Behavior
            appBehaviorSection
            
            // About
            aboutSection
        }
        .formStyle(.grouped)
        .frame(maxWidth: 700)
        .padding()
    }
    
    // MARK: - Python Section
    
    private var pythonSection: some View {
        Section {
            // Python status
            HStack {
                statusIndicator(for: pythonManager.status)
                Text(pythonManager.status.description)
                Spacer()
                if pythonManager.status == .initializing {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            
            // Use bundled vs system Python
            Toggle("Use Bundled Python", isOn: $settings.useBundledPython)
                .onChange(of: settings.useBundledPython) { _, _ in
                    Task {
                        await pythonManager.reinitialize()
                    }
                }
            
            // Python path
            if !settings.useBundledPython {
                HStack {
                    Text("Python Path")
                    Spacer()
                    Text(settings.pythonPath)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Browse...") {
                        showingPythonPathPicker = true
                    }
                }
                .fileImporter(
                    isPresented: $showingPythonPathPicker,
                    allowedContentTypes: [.unixExecutable, .item],
                    allowsMultipleSelection: false
                ) { result in
                    if case .success(let urls) = result, let url = urls.first {
                        settings.pythonPath = url.path
                    }
                }
            }
            
            // NAM package path
            HStack {
                Text("NAM Package Path")
                Spacer()
                if settings.namPackagePath.isEmpty {
                    Text("Auto-detect")
                        .foregroundColor(.secondary)
                } else {
                    Text(settings.namPackagePath)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Button("Browse...") {
                    showingNAMPathPicker = true
                }
            }
            .fileImporter(
                isPresented: $showingNAMPathPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    settings.namPackagePath = url.path
                }
            }
            
            // Test button
            HStack {
                Button {
                    testPythonEnvironment()
                } label: {
                    if isPythonTesting {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Text("Test Python Environment")
                    }
                }
                .disabled(isPythonTesting)
                
                if let result = pythonTestResult {
                    Text(result)
                        .font(.caption)
                        .foregroundColor(result.contains("✓") ? .green : .red)
                }
            }
            
            // Environment info
            if pythonManager.status.isReady {
                LabeledContent("Python Version", value: pythonManager.pythonVersion)
                LabeledContent("PyTorch Version", value: pythonManager.torchVersion)
                LabeledContent("NAM Version", value: pythonManager.namVersion.isEmpty ? "Not installed" : pythonManager.namVersion)
                LabeledContent("MPS (Apple GPU)", value: pythonManager.hasMPS ? "Available" : "Not Available")
            }
        } header: {
            Label("Python Configuration (Training Only)", systemImage: "terminal")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Python is only needed for TRAINING new NAM models.")
                Text("For using existing .nam models, you just need the NAM Audio Unit plugin installed.")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Folder Section
    
    private var folderSection: some View {
        Section {
            folderRow(
                title: "Processed Audio Folder",
                path: settings.defaultOutputFolder,
                showingPicker: $showingOutputFolderPicker
            ) { url in
                settings.defaultOutputFolder = url.path
            }
            
            folderRow(
                title: "Trained Models Folder",
                path: settings.defaultModelFolder,
                showingPicker: $showingModelFolderPicker
            ) { url in
                settings.defaultModelFolder = url.path
            }
            
            folderRow(
                title: "IR Folder",
                path: settings.defaultIRFolder,
                showingPicker: $showingIRFolderPicker
            ) { url in
                settings.defaultIRFolder = url.path
            }
            
            Button("Create Folders") {
                settings.createRequiredDirectories()
            }
        } header: {
            Label("Default Folders", systemImage: "folder")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("**Trained Models Folder** - Where your .nam models are saved after training.")
                Text("**Processed Audio Folder** - Where reamped audio files are saved.")
            }
        }
    }
    
    private func folderRow(
        title: String,
        path: String,
        showingPicker: Binding<Bool>,
        onSelect: @escaping (URL) -> Void
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(path)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 300, alignment: .trailing)
            
            Button("Browse...") {
                showingPicker.wrappedValue = true
            }
            
            Button {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
        }
        .fileImporter(
            isPresented: showingPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                onSelect(url)
            }
        }
    }
    
    // MARK: - Training Defaults Section
    
    private var trainingDefaultsSection: some View {
        Section {
            Picker("Default Architecture", selection: $settings.trainingArchitecture) {
                ForEach(ModelArchitecture.allCases, id: \.self) { arch in
                    Text(arch.rawValue).tag(arch)
                }
            }
            
            HStack {
                Text("Default Epochs")
                Spacer()
                TextField("Epochs", value: $settings.trainingEpochs, format: .number)
                    .frame(width: 80)
                    .textFieldStyle(.roundedBorder)
            }
        } header: {
            Label("Training Defaults", systemImage: "brain")
        }
    }
    
    // MARK: - Audio Units Section
    
    private var audioUnitsSection: some View {
        Section {
            HStack {
                Text("Available Audio Units")
                Spacer()
                Text("\(audioUnitManager.availableAudioUnits.count)")
                    .foregroundColor(.secondary)
            }
            
            if let lastScan = audioUnitManager.lastScanDate {
                HStack {
                    Text("Last Scanned")
                    Spacer()
                    Text(lastScan, style: .relative)
                        .foregroundColor(.secondary)
                }
            }
            
            Button {
                Task {
                    await audioUnitManager.scanForAudioUnits()
                }
            } label: {
                if audioUnitManager.isScanning {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Scanning...")
                    }
                } else {
                    Text("Rescan Audio Units")
                }
            }
            .disabled(audioUnitManager.isScanning)
            
            // NAM plugin status
            if let namAU = audioUnitManager.findNAMAudioUnit() {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("NAM Plugin Found")
                    Spacer()
                    Text(namAU.name)
                        .foregroundColor(.secondary)
                }
            } else {
                HStack {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundColor(.orange)
                    Text("NAM Plugin Not Found")
                    Spacer()
                }
            }
        } header: {
            Label("Audio Units", systemImage: "square.stack.3d.up")
        } footer: {
            Text("Audio Units are used for real-time processing and reamping. Install the NAM plugin for best results.")
        }
    }
    
    // MARK: - App Behavior Section
    
    private var appBehaviorSection: some View {
        Section {
            Toggle("Auto-save Chains", isOn: $settings.autoSaveChains)
            
            Picker("Preview Buffer Size", selection: $settings.previewBufferSize) {
                Text("128 samples").tag(128)
                Text("256 samples").tag(256)
                Text("512 samples").tag(512)
                Text("1024 samples").tag(1024)
                Text("2048 samples").tag(2048)
            }
            
            // Recent files
            if !settings.recentInputFiles.isEmpty {
                DisclosureGroup("Recent Files") {
                    ForEach(settings.recentInputFiles, id: \.self) { path in
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .foregroundColor(.secondary)
                    }
                    
                    Button("Clear Recent Files") {
                        settings.clearRecentFiles()
                    }
                }
            }
            
            Button("Reset All Settings") {
                settings.resetToDefaults()
            }
            .foregroundColor(.red)
        } header: {
            Label("App Behavior", systemImage: "gearshape")
        }
    }
    
    // MARK: - About Section
    
    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("Build")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                    .foregroundColor(.secondary)
            }
            
            Link(destination: URL(string: "https://github.com/sdatkinson/neural-amp-modeler")!) {
                HStack {
                    Text("NAM on GitHub")
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                }
            }
        } header: {
            Label("About", systemImage: "info.circle")
        }
    }
    
    // MARK: - Helpers
    
    private func statusIndicator(for status: PythonStatus) -> some View {
        Group {
            switch status {
            case .ready:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .error:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            case .initializing:
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundColor(.blue)
            case .notInitialized:
                Image(systemName: "circle")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func testPythonEnvironment() {
        isPythonTesting = true
        pythonTestResult = nil
        
        Task {
            do {
                let result = try await pythonManager.runPythonCommand("print('Hello from Python!')")
                await MainActor.run {
                    pythonTestResult = result.contains("Hello") ? "✓ Python is working" : "✗ Unexpected output"
                    isPythonTesting = false
                }
            } catch {
                await MainActor.run {
                    pythonTestResult = "✗ \(error.localizedDescription)"
                    isPythonTesting = false
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}
