//
//  ChainBuilderView.swift
//  NAM Reamp Lab
//
//  Created by Mitchell Cohen on 1/22/26.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// Main view for Tab 1 - Chain Builder and Reamping
struct ChainBuilderView: View {
    @StateObject private var chainManager = ChainManager.shared
    @StateObject private var audioUnitManager = AudioUnitHostManager.shared
    @StateObject private var audioEngine = AudioEngine.shared
    
    @State private var showingInputFilePicker = false
    @State private var showingOutputFolderPicker = false
    @State private var showingAddPluginSheet = false
    @State private var showingExportSheet = false
    @State private var showingImportSheet = false
    @State private var showingPluginUI = false
    @State private var selectedPluginIndex: Int?
    @State private var processingError: String?
    @State private var showingError = false
    @State private var showingModelNamingSheet = false
    @State private var modelNames: [UUID: String] = [:]  // Chain ID -> Model name
    
    var body: some View {
        VStack(spacing: 0) {
            // Top: Audio I/O Panel
            AudioIOView()
            
            Divider()
            
            // Main content
            HSplitView {
                // Left sidebar - Chain list
                chainListSidebar
                    .frame(minWidth: 220, idealWidth: 280, maxWidth: 350)
                
                // Right side - Chain detail
                chainDetailView
                    .frame(minWidth: 400)
            }
            
            Divider()
            
            // Bottom: Workflow Action Bar
            workflowActionBar
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                toolbarItems
            }
        }
        .sheet(isPresented: $showingAddPluginSheet) {
            AddPluginSheet(chain: chainManager.selectedChain)
        }
        .sheet(isPresented: $showingPluginUI) {
            if let index = selectedPluginIndex,
               index < audioEngine.loadedAudioUnits.count,
               let chain = chainManager.selectedChain,
               index < chain.plugins.count {
                PluginUIHostView(
                    audioUnit: audioEngine.loadedAudioUnits[index],
                    name: chain.plugins[index].name
                )
                .frame(minWidth: 600, minHeight: 400)
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(processingError ?? "Unknown error")
        }
        .sheet(isPresented: $showingModelNamingSheet) {
            ModelNamingSheet(
                chains: chainManager.enabledChains,
                modelNames: $modelNames,
                onConfirm: {
                    showingModelNamingSheet = false
                    Task {
                        await executeProcessAndTrain()
                    }
                },
                onCancel: {
                    showingModelNamingSheet = false
                }
            )
        }
        .onChange(of: chainManager.selectedChainId) { oldId, newId in
            // Load chain into audio engine when selection changes
            // Only reload if the ID actually changed (not just the chain content)
            guard oldId != newId, let newId = newId else { return }
            guard let chain = chainManager.chains.first(where: { $0.id == newId }) else { return }
            
            // Don't reload during processing
            guard !chainManager.isProcessing else { return }
            
            Task {
                // Small delay to avoid publishing during view updates
                try? await Task.sleep(for: .milliseconds(50))
                do {
                    try await audioEngine.loadChain(chain)
                } catch {
                    await MainActor.run {
                        processingError = error.localizedDescription
                        showingError = true
                    }
                }
            }
        }
    }
    
    // MARK: - Chain List Sidebar
    
    private var chainListSidebar: some View {
        VStack(spacing: 0) {
            // Input file section
            inputFileSection
            
            Divider()
            
            // Chain list
            List(selection: $chainManager.selectedChainId) {
                Section("Processing Chains") {
                    ForEach(chainManager.chains) { chain in
                        ChainRowView(chain: chain)
                            .tag(chain.id)
                            .contextMenu {
                                chainContextMenu(for: chain)
                            }
                    }
                    .onDelete(perform: chainManager.deleteChains)
                    .onMove(perform: chainManager.moveChains)
                }
            }
            .listStyle(.sidebar)
            
            Divider()
            
            // Chain list actions
            chainListActions
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var inputFileSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "waveform.circle.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("Input Audio")
                    .font(.headline)
            }
            
            if let url = chainManager.inputFileURL {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(url.lastPathComponent)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(url.deletingLastPathComponent().lastPathComponent)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button {
                        chainManager.inputFileURL = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove input file")
                }
                .padding(10)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(8)
            } else {
                Button {
                    openInputFilePicker()
                } label: {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("Select DI Recording")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
            }
            
            Text("The clean DI signal to process through your chains")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
    
    private func openInputFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .wav, .aiff, .mp3]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Select an input audio file for training"
        panel.prompt = "Select"
        
        if panel.runModal() == .OK, let url = panel.url {
            chainManager.inputFileURL = url
            AppSettings.shared.addRecentInputFile(url.path)
        }
    }
    
    private func openImportChainPicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "namchain") ?? .json, .json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Import a chain preset"
        panel.prompt = "Import"
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try chainManager.importChain(from: url)
            } catch {
                processingError = error.localizedDescription
                showingError = true
            }
        }
    }
    
    private var chainListActions: some View {
        VStack(spacing: 8) {
            // New chain button - prominent
            Button {
                chainManager.createChain()
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("New Chain")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            
            // Secondary actions
            HStack(spacing: 8) {
                Button {
                    openImportChainPicker()
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button {
                    if let chain = chainManager.selectedChain {
                        exportChain(chain)
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(chainManager.selectedChain == nil)
            }
        }
        .padding(12)
    }
    
    private func exportChain(_ chain: ProcessingChain) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "namchain") ?? .json]
        panel.nameFieldStringValue = "\(chain.name).namchain"
        panel.message = "Export chain preset"
        panel.prompt = "Export"
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try chainManager.exportChain(chain, to: url)
            } catch {
                processingError = error.localizedDescription
                showingError = true
            }
        }
    }
    
    @ViewBuilder
    private func chainContextMenu(for chain: ProcessingChain) -> some View {
        Button {
            exportChain(chain)
        } label: {
            Label("Save Chain...", systemImage: "square.and.arrow.down")
        }
        
        Button {
            chainManager.toggleChain(chain)
        } label: {
            Label(chain.isEnabled ? "Disable" : "Enable", 
                  systemImage: chain.isEnabled ? "eye.slash" : "eye")
        }
        
        Button {
            chainManager.duplicateChain(chain)
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }
        
        Divider()
        
        Button(role: .destructive) {
            chainManager.deleteChain(chain)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
    
    // MARK: - Chain Detail View
    
    @ViewBuilder
    private var chainDetailView: some View {
        if let chain = chainManager.selectedChain {
            ChainDetailView(chain: binding(for: chain))
        } else {
            emptyStateView
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            Text("No Chain Selected")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text("Select a chain from the sidebar or create a new one")
                .foregroundColor(.secondary)
            
            Button {
                chainManager.createChain()
            } label: {
                Label("Create New Chain", systemImage: "plus")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Workflow Action Bar
    
    private var workflowActionBar: some View {
        HStack(spacing: 16) {
            // Status section
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(chainManager.inputFileURL != nil ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(chainManager.inputFileURL != nil ? "Input ready" : "No input file")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 6) {
                    Circle()
                        .fill(chainManager.enabledChains.count > 0 ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text("\(chainManager.enabledChains.count) chain\(chainManager.enabledChains.count == 1 ? "" : "s") enabled")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Progress indicator when processing
            if chainManager.isProcessing {
                HStack(spacing: 8) {
                    ProgressView(value: chainManager.processingProgress)
                        .frame(width: 120)
                    Text("\(Int(chainManager.processingProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                        .frame(width: 35, alignment: .trailing)
                    Text(chainManager.currentProcessingChain)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            // Main action button - process chains and train models
            Button {
                // Initialize model names with chain names (skip defaults)
                modelNames = Dictionary(uniqueKeysWithValues: 
                    chainManager.enabledChains.map { chain in
                        let isDefaultName = chain.name.hasPrefix("New Chain") && 
                                          (chain.name == "New Chain" || chain.name.hasSuffix(" Copy"))
                        return (chain.id, isDefaultName ? "" : chain.name)
                    }
                )
                showingModelNamingSheet = true
            } label: {
                Label("Process & Train", systemImage: "brain")
                    .frame(minWidth: 130)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(chainManager.inputFileURL == nil || chainManager.enabledChains.isEmpty || chainManager.isProcessing)
            .help("Process audio through all enabled chains and train NAM models for each")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Toolbar
    
    @ViewBuilder
    private var toolbarItems: some View {
        Button {
            showingAddPluginSheet = true
        } label: {
            Label("Add Plugin", systemImage: "plus.app")
        }
        .disabled(chainManager.selectedChain == nil)
        
        Button {
            openImportChainPicker()
        } label: {
            Label("Import", systemImage: "square.and.arrow.down")
        }
        .help("Import a chain preset")
    }
    
    // MARK: - Helper Methods
    
    private func binding(for chain: ProcessingChain) -> Binding<ProcessingChain> {
        Binding(
            get: { chain },
            set: { chainManager.selectedChain = $0 }
        )
    }
    
    private func handleInputFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                chainManager.inputFileURL = url
                AppSettings.shared.addRecentInputFile(url.path)
            }
        case .failure(let error):
            processingError = error.localizedDescription
            showingError = true
        }
    }
    
    private func handleChainImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                do {
                    try chainManager.importChain(from: url)
                } catch {
                    processingError = error.localizedDescription
                    showingError = true
                }
            }
        case .failure(let error):
            processingError = error.localizedDescription
            showingError = true
        }
    }
    
    private func processAllChains() async {
        let outputFolder = URL(fileURLWithPath: AppSettings.shared.defaultOutputFolder)
        
        // Create output folder if it doesn't exist
        try? FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
        
        print("🎛️ Processing chains...")
        print("   Input: \(chainManager.inputFileURL?.path ?? "none")")
        print("   Output folder: \(outputFolder.path)")
        print("   Enabled chains: \(chainManager.enabledChains.count)")
        
        do {
            let outputURLs = try await chainManager.processAllEnabledChains(outputFolder: outputFolder)
            print("✅ Processed \(outputURLs.count) chains:")
            for url in outputURLs {
                print("   - \(url.lastPathComponent)")
            }
        } catch {
            print("❌ Processing failed: \(error)")
            processingError = error.localizedDescription
            showingError = true
        }
    }
    
    private func executeProcessAndTrain() async {
        let outputFolder = URL(fileURLWithPath: AppSettings.shared.defaultOutputFolder)
        
        // Create output folder if it doesn't exist
        try? FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
        
        print("🎛️ Process & Train workflow starting...")
        print("   Input: \(chainManager.inputFileURL?.path ?? "none")")
        print("   Output folder: \(outputFolder.path)")
        print("   Enabled chains: \(chainManager.enabledChains.count)")
        for chain in chainManager.enabledChains {
            print("   - \(chain.name): \(chain.plugins.count) plugins -> Model: \(modelNames[chain.id] ?? chain.name)")
        }
        
        do {
            // Process all enabled chains
            print("📼 Processing audio through chains...")
            let outputURLs = try await chainManager.processAllEnabledChains(outputFolder: outputFolder)
            
            guard !outputURLs.isEmpty else {
                processingError = "No output files were generated"
                showingError = true
                return
            }
            
            print("✅ Processed \(outputURLs.count) chains:")
            for url in outputURLs {
                print("   - \(url.lastPathComponent)")
            }
            
            // Create training jobs for each output with custom names
            let trainer = NAMTrainer.shared
            guard let inputURL = chainManager.inputFileURL else {
                print("❌ No input file URL!")
                return
            }
            
            print("🧠 Creating training jobs...")
            for (index, outputURL) in outputURLs.enumerated() {
                let chain = chainManager.enabledChains[safe: index]
                let chainName = chain?.name ?? "Chain \(index + 1)"
                let modelName = chain.flatMap { modelNames[$0.id] } ?? chainName
                
                print("   Creating job: \(chainName)")
                print("     Input (DI): \(inputURL.path)")
                print("     Output (Reamped): \(outputURL.path)")
                print("     Model name: \(modelName)")
                
                trainer.createJob(
                    inputFilePath: inputURL.path,
                    outputFilePath: outputURL.path,
                    modelName: modelName,
                    chainName: chainName
                )
            }
            
            // Switch to Training tab
            NotificationCenter.default.post(name: .switchToTrainingTab, object: nil)
            
            print("✅ Created \(outputURLs.count) training jobs - switching to Training tab")
        } catch {
            print("❌ Process & Train failed: \(error)")
            processingError = error.localizedDescription
            showingError = true
        }
    }
}

// MARK: - Safe Array Access
extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let switchToTrainingTab = Notification.Name("switchToTrainingTab")
}

// MARK: - Chain Row View

struct ChainRowView: View {
    let chain: ProcessingChain
    
    var body: some View {
        HStack {
            Image(systemName: chain.isEnabled ? "checkmark.circle.fill" : "circle")
                .foregroundColor(chain.isEnabled ? .green : .secondary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(chain.name)
                    .fontWeight(.medium)
                
                Text("\(chain.plugins.count) plugin\(chain.plugins.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .opacity(chain.isEnabled ? 1.0 : 0.6)
    }
}

// MARK: - Chain Detail View

struct ChainDetailView: View {
    @Binding var chain: ProcessingChain
    @StateObject private var chainManager = ChainManager.shared
    @State private var isEditingName = false
    @State private var editedName = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            chainHeader
            
            Divider()
            
            // Plugin list
            if chain.plugins.isEmpty {
                emptyPluginList
            } else {
                pluginList
            }
        }
    }
    
    private var chainHeader: some View {
        HStack {
            if isEditingName {
                TextField("Chain Name", text: $editedName, onCommit: {
                    chainManager.renameChain(chain, to: editedName)
                    isEditingName = false
                })
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
            } else {
                Text(chain.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .onTapGesture(count: 2) {
                        editedName = chain.name
                        isEditingName = true
                    }
            }
            
            Spacer()
            
            Toggle("Enabled", isOn: Binding(
                get: { chain.isEnabled },
                set: { _ in chainManager.toggleChain(chain) }
            ))
            .toggleStyle(.switch)
        }
        .padding()
    }
    
    private var emptyPluginList: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No Plugins")
                .font(.title3)
                .foregroundColor(.secondary)
            
            Text("Add NAM models, Audio Units, or Impulse Responses")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var pluginList: some View {
        List {
            ForEach(Array(chain.plugins.enumerated()), id: \.element.id) { index, plugin in
                PluginRowView(
                    plugin: plugin,
                    index: index,
                    onToggle: { chainManager.togglePlugin(plugin, in: chain) },
                    onBypass: { chainManager.toggleBypass(plugin, in: chain) },
                    onRemove: { chainManager.removePlugin(plugin, from: chain) }
                )
            }
            .onMove { source, destination in
                chainManager.movePlugins(in: chain, from: source, to: destination)
            }
        }
    }
}

// MARK: - Plugin Row View

struct PluginRowView: View {
    let plugin: AudioPlugin
    let index: Int
    let onToggle: () -> Void
    let onBypass: () -> Void
    let onRemove: () -> Void
    var onShowUI: (() -> Void)? = nil
    
    @StateObject private var audioEngine = AudioEngine.shared
    @State private var showingPluginUI = false
    @State private var isEditingNickname = false
    @State private var editedNickname = ""
    
    var body: some View {
        HStack(spacing: 12) {
            // Index
            Text("\(index + 1)")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 20)
            
            // Plugin icon
            Image(systemName: plugin.type.icon)
                .font(.title3)
                .foregroundColor(iconColor)
                .frame(width: 24)
            
            // Plugin info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    if isEditingNickname {
                        TextField("Nickname", text: $editedNickname, onCommit: {
                            updateNickname()
                        })
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .frame(width: 150)
                    } else {
                        Text(plugin.nickname ?? plugin.name)
                            .fontWeight(.medium)
                            .strikethrough(plugin.isBypassed)
                            .onTapGesture(count: 2) {
                                editedNickname = plugin.nickname ?? plugin.name
                                isEditingNickname = true
                            }
                        
                        if plugin.nickname != nil {
                            Text("(\(plugin.name))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .italic()
                        }
                    }
                }
                
                HStack(spacing: 8) {
                    Text(plugin.type.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let path = plugin.path {
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer()
            
            // Show plugin UI button (for Audio Units)
            if plugin.type == .audioUnit || plugin.type == .nam {
                Button {
                    showPluginUI()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.borderless)
                .help("Open plugin UI")
            }
            
            // Bypass button
            Button {
                onBypass()
            } label: {
                Image(systemName: plugin.isBypassed ? "forward.fill" : "forward")
                    .foregroundColor(plugin.isBypassed ? .orange : .secondary)
            }
            .buttonStyle(.borderless)
            .help(plugin.isBypassed ? "Enable" : "Bypass")
            
            // Remove button
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Remove plugin")
        }
        .padding(.vertical, 4)
        .opacity(plugin.isEnabled && !plugin.isBypassed ? 1.0 : 0.6)
        .contentShape(Rectangle())  // Make entire row tappable
        .onTapGesture(count: 2) {
            // Double-click anywhere on row to open UI
            if plugin.type == .audioUnit || plugin.type == .nam {
                showPluginUI()
            }
        }
    }
    
    private func updateNickname() {
        isEditingNickname = false
        if let chain = ChainManager.shared.selectedChain {
            ChainManager.shared.updatePluginNickname(plugin, in: chain, nickname: editedNickname.isEmpty ? nil : editedNickname)
        }
    }
    
    private var iconColor: Color {
        switch plugin.type {
        case .nam: return .purple
        case .audioUnit: return .blue
        case .impulseResponse: return .orange
        }
    }
    
    private func showPluginUI() {
        // Show the Audio Unit UI in a floating window
        Task {
            guard index < audioEngine.loadedAudioUnits.count else { return }
            
            if let viewController = await audioEngine.getAudioUnitViewController(at: index) {
                await MainActor.run {
                    let window = NSWindow(contentViewController: viewController)
                    window.title = plugin.name
                    window.styleMask = [.titled, .closable, .resizable]
                    window.setContentSize(viewController.preferredContentSize)
                    window.center()
                    window.makeKeyAndOrderFront(nil)
                }
            }
        }
    }
}

// MARK: - Add Plugin Sheet

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
        VStack {
            Button {
                openNAMModelPicker()
            } label: {
                Label("Browse for NAM Models...", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding()
            
            Spacer()
            
            VStack(spacing: 8) {
                Image(systemName: "waveform.badge.mic")
                    .font(.largeTitle)
                    .foregroundColor(.purple)
                Text("Select .nam model files to add to the chain")
                    .foregroundColor(.secondary)
                Text("These models will be loaded into the NAM Audio Unit")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
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

// MARK: - Model Naming Sheet

struct ModelNamingSheet: View {
    let chains: [ProcessingChain]
    @Binding var modelNames: [UUID: String]
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    @State private var localNames: [UUID: String] = [:]
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Name Your Models")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Enter names for each model before processing. Leave blank to use chain name.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(chains) { chain in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(chain.name)
                                    .font(.headline)
                                Spacer()
                                Text("\(chain.plugins.count) plugin\(chain.plugins.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            TextField("Model name (leave empty to use chain name)", 
                                    text: Binding(
                                        get: { localNames[chain.id] ?? modelNames[chain.id] ?? "" },
                                        set: { localNames[chain.id] = $0 }
                                    ))
                            .textFieldStyle(.roundedBorder)
                            
                            if let name = localNames[chain.id], !name.isEmpty {
                                Text("Will save as: \(name.replacingOccurrences(of: " ", with: "_")).nam")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            } else if !(modelNames[chain.id] ?? "").isEmpty {
                                Text("Will save as: \(modelNames[chain.id]!.replacingOccurrences(of: " ", with: "_")).nam")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            } else {
                                Text("Will save as: \(chain.name.replacingOccurrences(of: " ", with: "_")).nam")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
            .frame(maxHeight: 400)
            
            HStack(spacing: 16) {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Start Processing") {
                    // Update model names with local edits
                    for (id, name) in localNames where !name.isEmpty {
                        modelNames[id] = name
                    }
                    onConfirm()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(30)
        .frame(width: 600)
    }
}

// MARK: - Preview

#Preview {
    ChainBuilderView()
}
