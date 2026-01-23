//
//  AddPluginSheet.swift
//  NAM Reamp Lab
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AddPluginSheet: View {
    let chain: ProcessingChain?
    @Environment(\.dismiss) private var dismiss
    @StateObject private var chainManager = ChainManager.shared
    @StateObject private var audioUnitManager = AudioUnitHostManager.shared
    
    @State private var selectedTab = 0
    @State private var searchText = ""
    @State private var showingFilePicker = false
    @State private var filePickerType: PluginType = .nam
    
    // Keyboard navigation
    @State private var selectedIndex: Int?
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Plugin")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Done") {
                    dismiss()
                }
            }
            .padding()
            
            Divider()
            
            // Tab picker
            Picker("Plugin Type", selection: $selectedTab) {
                Text("NAM Models").tag(0)
                Text("Audio Units").tag(1)
                Text("Impulse Responses").tag(2)
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Search
            TextField("Search...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .focused($isSearchFocused)
                .onSubmit {
                    handleEnter()
                }
            
            // Content
            Group {
                switch selectedTab {
                case 0:
                    namModelsList
                case 1:
                    audioUnitsList
                case 2:
                    impulseResponsesList
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                // Capture arrow keys
                KeyEventView { event in
                    handleKeyEvent(event)
                }
                .frame(width: 0, height: 0)
            )
        }
        .frame(width: 500, height: 500)
        .onAppear {
            isSearchFocused = true
        }
        .onChange(of: searchText) { old, new in
            selectedIndex = nil
        }
        .task {
            if audioUnitManager.availableAudioUnits.isEmpty {
                await audioUnitManager.scanForAudioUnits()
            }
        }
    }
    
    private func handleEnter() {
        let results = filteredAudioUnits
        if results.isEmpty { return }
        
        if let current = selectedIndex {
            // Third enter (confirm load)
            if current >= 0 && current < results.count {
                addAudioUnit(results[current])
            }
        } else {
            // Second enter (jump to first result)
            selectedIndex = 0
        }
    }
    
    private func handleKeyEvent(_ event: NSEvent) {
        let results = filteredAudioUnits
        if results.isEmpty { return }
        
        if event.keyCode == 125 { // Down arrow
            if let current = selectedIndex {
                selectedIndex = min(current + 1, results.count - 1)
            } else {
                selectedIndex = 0
            }
        } else if event.keyCode == 126 { // Up arrow
            if let current = selectedIndex {
                selectedIndex = max(current - 1, 0)
            }
        }
    }
    
    private var namModelsList: some View {
        VStack(spacing: 0) {
            let modelFolder = URL(fileURLWithPath: AppSettings.shared.defaultModelFolder)
            
            if FileManager.default.fileExists(atPath: modelFolder.path) {
                FileBrowserView(rootURL: modelFolder, fileExtension: "nam") { url in
                    if let chain = chain {
                        let plugin = AudioPlugin(
                            name: url.deletingPathExtension().lastPathComponent,
                            type: .nam,
                            path: url.path
                        )
                        chainManager.addPlugin(plugin, to: chain)
                    }
                }
            } else {
                VStack(spacing: 20) {
                    Spacer()
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Default model folder not found")
                        .font(.headline)
                    Text(modelFolder.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Select Folder in Settings") {
                        // Ideally link to settings
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
            }
            
            Divider()
            
            Button {
                openNAMModelPicker()
            } label: {
                Label("Browse for other NAM Models...", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .padding(10)
        }
    }
    
    private func openNAMModelPicker() {
        guard let chain = chain else { return }
        
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "nam") ?? .data]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Select NAM model files"
        panel.prompt = "Add"
        
        // Try default model folder first
        let modelFolder = AppSettings.shared.defaultModelFolder
        if FileManager.default.fileExists(atPath: modelFolder) {
            panel.directoryURL = URL(fileURLWithPath: modelFolder)
        }
        
        if panel.runModal() == .OK {
            for url in panel.urls {
                let plugin = AudioPlugin(
                    name: url.deletingPathExtension().lastPathComponent,
                    type: .nam,
                    path: url.path
                )
                chainManager.addPlugin(plugin, to: chain)
            }
        }
    }
    
    private var audioUnitsList: some View {
        ScrollViewReader { proxy in
            List(selection: $selectedIndex) {
                let results = filteredAudioUnits
                ForEach(Array(results.enumerated()), id: \.offset) { index, au in
                    Button {
                        addAudioUnit(au)
                    } label: {
                        HStack {
                            Image(systemName: au.icon)
                                .foregroundColor(.blue)
                            VStack(alignment: .leading) {
                                Text(au.name)
                                Text(au.manufacturer)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "plus.circle")
                                .foregroundColor(.accentColor)
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(selectedIndex == index ? Color.accentColor.opacity(0.2) : Color.clear)
                    .id(index)
                }
            }
            .onChange(of: selectedIndex) { old, new in
                if let new = new {
                    proxy.scrollTo(new)
                }
            }
        }
    }
    
    private var filteredAudioUnits: [AudioUnitInfo] {
        if searchText.isEmpty {
            return audioUnitManager.availableAudioUnits
        }
        return audioUnitManager.availableAudioUnits.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.manufacturer.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private var impulseResponsesList: some View {
        VStack {
            Button {
                openIRPicker()
            } label: {
                Label("Browse for Impulse Responses...", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding()
            
            Spacer()
            
            VStack(spacing: 8) {
                Image(systemName: "waveform.path")
                    .font(.largeTitle)
                    .foregroundColor(.orange)
                Text("Select .wav or .aiff impulse response files")
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
    
    private func openIRPicker() {
        guard let chain = chain else { return }
        
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .wav, .aiff]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Select impulse response files"
        panel.prompt = "Add"
        
        // Try default IR folder first
        let irFolder = AppSettings.shared.defaultIRFolder
        if FileManager.default.fileExists(atPath: irFolder) {
            panel.directoryURL = URL(fileURLWithPath: irFolder)
        }
        
        if panel.runModal() == .OK {
            for url in panel.urls {
                let plugin = AudioPlugin(
                    name: url.deletingPathExtension().lastPathComponent,
                    type: .impulseResponse,
                    path: url.path
                )
                chainManager.addPlugin(plugin, to: chain)
            }
        }
    }
    
    private func handleFileSelection(_ result: Result<[URL], Error>) {
        guard let chain = chain else { return }
        
        switch result {
        case .success(let urls):
            for url in urls {
                let plugin = AudioPlugin(
                    name: url.deletingPathExtension().lastPathComponent,
                    type: filePickerType,
                    path: url.path
                )
                chainManager.addPlugin(plugin, to: chain)
            }
        case .failure(let error):
            print("File selection error: \(error)")
        }
    }
    
    private func addAudioUnit(_ info: AudioUnitInfo) {
        guard let chain = chain else { return }
        
        let plugin = AudioPlugin(
            name: info.name,
            type: .audioUnit,
            componentDescription: AudioComponentDescriptionCodable(from: info.componentDescription)
        )
        chainManager.addPlugin(plugin, to: chain)
    }
}

/// Helper view to capture global key events in a window
struct KeyEventView: NSViewRepresentable {
    let onKeyEvent: (NSEvent) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = KeyEventNSView()
        view.onKeyEvent = onKeyEvent
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
    
    class KeyEventNSView: NSView {
        var onKeyEvent: ((NSEvent) -> Void)?
        
        override var acceptsFirstResponder: Bool { true }
        
        override func keyDown(with event: NSEvent) {
            onKeyEvent?(event)
        }
    }
}
