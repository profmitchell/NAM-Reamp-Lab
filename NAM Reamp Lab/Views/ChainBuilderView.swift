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
                // Favorites Group
                let favorites = chainManager.chains.filter { chain in 
                    chain.plugins.contains(where: { $0.isFavorite })
                }
                
                if !favorites.isEmpty {
                    Section("Favorites") {
                        ForEach(favorites) { chain in
                            ChainRowView(chain: chain)
                                .tag(chain.id)
                        }
                    }
                }
                
                let groups = chainManager.availableGroups
                
                // Grouped Chains
                ForEach(groups, id: \.self) { group in
                    Section(group) {
                        ForEach(chainManager.chains.filter { $0.groupName == group }) { chain in
                            ChainRowView(chain: chain)
                                .tag(chain.id)
                                .contextMenu {
                                    chainContextMenu(for: chain)
                                }
                        }
                    }
                }
                
                // Ungrouped Chains
                Section("All Chains") {
                    ForEach(chainManager.chains.filter { $0.groupName == nil }) { chain in
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
        
        Menu {
            Button("None") {
                chainManager.updateChainGroup(chain, to: nil)
            }
            Divider()
            ForEach(chainManager.availableGroups, id: \.self) { group in
                Button(group) {
                    chainManager.updateChainGroup(chain, to: group)
                }
            }
            Divider()
            Button("New Group...") {
                // We'd ideally show an alert here, but for now we can just use a prompt
                let alert = NSAlert()
                alert.messageText = "New Group Name"
                alert.addButton(withTitle: "Create")
                alert.addButton(withTitle: "Cancel")
                let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
                alert.accessoryView = input
                if alert.runModal() == .alertFirstButtonReturn {
                    chainManager.updateChainGroup(chain, to: input.stringValue)
                }
            }
        } label: {
            Label("Move to Group", systemImage: "folder")
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

#Preview {
    ChainBuilderView()
}
