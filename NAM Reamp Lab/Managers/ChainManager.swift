//
//  ChainManager.swift
//  NAM Reamp Lab
//
//  Created by Mitchell Cohen on 1/22/26.
//

import Foundation
import Combine
import SwiftUI

/// Manages processing chains with persistence
@MainActor
class ChainManager: ObservableObject {
    static let shared = ChainManager()
    
    // MARK: - Published Properties
    
    @Published var chains: [ProcessingChain] = []
    @Published var selectedChainId: UUID?
    @Published private(set) var isProcessing: Bool = false
    @Published private(set) var processingProgress: Double = 0.0
    @Published private(set) var currentProcessingChain: String = ""
    @Published var inputFileURL: URL?
    
    // MARK: - Computed Properties
    
    var selectedChain: ProcessingChain? {
        get {
            chains.first { $0.id == selectedChainId }
        }
        set {
            if let chain = newValue, let index = chains.firstIndex(where: { $0.id == chain.id }) {
                chains[index] = chain
            }
        }
    }
    
    var enabledChains: [ProcessingChain] {
        chains.filter { $0.isEnabled }
    }
    
    // MARK: - Private Properties
    
    private let chainsFileURL: URL
    private var cancellables = Set<AnyCancellable>()
    private let audioUnitManager = AudioUnitHostManager.shared
    
    // MARK: - Initialization
    
    private init() {
        // Set up chains file path
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let appFolder = documentsPath.appendingPathComponent("NAM Reamp Lab")
        chainsFileURL = appFolder.appendingPathComponent("chains.json")
        
        // Create app folder if needed
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        
        // Auto-load default input file if it exists
        let defaultInputPath = "/Users/Shared/CohenConcepts/NAM Reamp Lab/input.wav"
        if FileManager.default.fileExists(atPath: defaultInputPath) {
            inputFileURL = URL(fileURLWithPath: defaultInputPath)
        }
        
        // Defer loading chains to avoid publishing during view updates
        // when the singleton is first accessed from a SwiftUI view
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            self.loadChains()
            self.setupAutoSave()
        }
    }
    
    // MARK: - Chain Management
    
    /// Creates a new chain
    @discardableResult
    func createChain(name: String = "New Chain") -> ProcessingChain {
        let chain = ProcessingChain(name: name)
        chains.append(chain)
        selectedChainId = chain.id
        return chain
    }
    
    /// Duplicates an existing chain
    @discardableResult
    func duplicateChain(_ chain: ProcessingChain) -> ProcessingChain {
        let newChain = ProcessingChain(
            name: "\(chain.name) Copy",
            isEnabled: chain.isEnabled,
            plugins: chain.plugins
        )
        chains.append(newChain)
        selectedChainId = newChain.id
        return newChain
    }
    
    /// Deletes a chain
    func deleteChain(_ chain: ProcessingChain) {
        chains.removeAll { $0.id == chain.id }
        if selectedChainId == chain.id {
            selectedChainId = chains.first?.id
        }
    }
    
    /// Deletes chains at offsets
    func deleteChains(at offsets: IndexSet) {
        let idsToDelete = offsets.map { chains[$0].id }
        chains.remove(atOffsets: offsets)
        if let selectedId = selectedChainId, idsToDelete.contains(selectedId) {
            selectedChainId = chains.first?.id
        }
    }
    
    /// Moves chains
    func moveChains(from source: IndexSet, to destination: Int) {
        chains.move(fromOffsets: source, toOffset: destination)
    }
    
    /// Toggles a chain's enabled state
    func toggleChain(_ chain: ProcessingChain) {
        if let index = chains.firstIndex(where: { $0.id == chain.id }) {
            chains[index].isEnabled.toggle()
        }
    }
    
    /// Renames a chain
    func renameChain(_ chain: ProcessingChain, to newName: String) {
        if let index = chains.firstIndex(where: { $0.id == chain.id }) {
            chains[index].name = newName
            chains[index].modifiedAt = Date()
        }
    }
    
    // MARK: - Plugin Management
    
    /// Adds a plugin to the selected chain
    func addPlugin(_ plugin: AudioPlugin, to chain: ProcessingChain) {
        if let index = chains.firstIndex(where: { $0.id == chain.id }) {
            chains[index].plugins.append(plugin)
            chains[index].modifiedAt = Date()
        }
    }
    
    /// Removes a plugin from a chain
    func removePlugin(_ plugin: AudioPlugin, from chain: ProcessingChain) {
        if let chainIndex = chains.firstIndex(where: { $0.id == chain.id }),
           let pluginIndex = chains[chainIndex].plugins.firstIndex(where: { $0.id == plugin.id }) {
            chains[chainIndex].plugins.remove(at: pluginIndex)
            chains[chainIndex].modifiedAt = Date()
        }
    }
    
    /// Moves plugins within a chain
    func movePlugins(in chain: ProcessingChain, from source: IndexSet, to destination: Int) {
        if let index = chains.firstIndex(where: { $0.id == chain.id }) {
            chains[index].plugins.move(fromOffsets: source, toOffset: destination)
            chains[index].modifiedAt = Date()
        }
    }
    
    /// Toggles a plugin's enabled state
    func togglePlugin(_ plugin: AudioPlugin, in chain: ProcessingChain) {
        if let chainIndex = chains.firstIndex(where: { $0.id == chain.id }),
           let pluginIndex = chains[chainIndex].plugins.firstIndex(where: { $0.id == plugin.id }) {
            chains[chainIndex].plugins[pluginIndex].isEnabled.toggle()
            chains[chainIndex].modifiedAt = Date()
        }
    }
    
    /// Toggles a plugin's bypass state
    func toggleBypass(_ plugin: AudioPlugin, in chain: ProcessingChain) {
        if let chainIndex = chains.firstIndex(where: { $0.id == chain.id }),
           let pluginIndex = chains[chainIndex].plugins.firstIndex(where: { $0.id == plugin.id }) {
            chains[chainIndex].plugins[pluginIndex].isBypassed.toggle()
            chains[chainIndex].modifiedAt = Date()
        }
    }
    
    // MARK: - Processing
    
    /// Processes all enabled chains
    func processAllEnabledChains(outputFolder: URL) async throws -> [URL] {
        guard let inputURL = inputFileURL else {
            print("❌ ChainManager: No input file set")
            throw ChainError.noInputFile
        }
        
        guard !enabledChains.isEmpty else {
            print("❌ ChainManager: No chains enabled")
            throw ChainError.noChainsEnabled
        }
        
        // CRITICAL: Capture current plugin states BEFORE processing
        // This ensures we use the exact settings the user has configured
        captureCurrentChainState()
        saveChains()
        
        print("📼 ChainManager: Starting offline processing...")
        print("   Input file: \(inputURL.path)")
        print("   Output folder: \(outputFolder.path)")
        
        isProcessing = true
        processingProgress = 0.0
        
        defer {
            isProcessing = false
            processingProgress = 0.0
            currentProcessingChain = ""
        }
        
        var outputURLs: [URL] = []
        let totalChains = enabledChains.count
        
        for (index, chain) in enabledChains.enumerated() {
            currentProcessingChain = chain.name
            print("🔊 Processing chain \(index + 1)/\(totalChains): \(chain.name)")
            print("   Plugins: \(chain.plugins.map { $0.name }.joined(separator: " → "))")
            
            // Debug: Check if plugins have saved state
            for plugin in chain.plugins where plugin.type == .audioUnit {
                if plugin.presetData != nil {
                    print("   ✓ Plugin '\(plugin.name)' has saved preset data")
                } else {
                    print("   ⚠️ Plugin '\(plugin.name)' has NO preset data - will use default settings!")
                }
            }
            
            let outputURL = outputFolder.appendingPathComponent(chain.outputFileName)
            print("   Output: \(outputURL.lastPathComponent)")
            
            try await audioUnitManager.processAudioFile(
                inputURL: inputURL,
                outputURL: outputURL,
                plugins: chain.plugins
            ) { pluginProgress in
                let chainProgress = Double(index) / Double(totalChains)
                let pluginContribution = pluginProgress / Double(totalChains)
                self.processingProgress = chainProgress + pluginContribution
            }
            
            outputURLs.append(outputURL)
            processingProgress = Double(index + 1) / Double(totalChains)
            print("   ✓ Chain complete")
        }
        
        print("✅ ChainManager: All chains processed")
        return outputURLs
    }
    
    /// Processes a single chain
    func processChain(_ chain: ProcessingChain, outputFolder: URL) async throws -> URL {
        guard let inputURL = inputFileURL else {
            throw ChainError.noInputFile
        }
        
        isProcessing = true
        processingProgress = 0.0
        currentProcessingChain = chain.name
        
        defer {
            isProcessing = false
            processingProgress = 0.0
            currentProcessingChain = ""
        }
        
        let outputURL = outputFolder.appendingPathComponent(chain.outputFileName)
        
        try await audioUnitManager.processAudioFile(
            inputURL: inputURL,
            outputURL: outputURL,
            plugins: chain.plugins
        ) { progress in
            self.processingProgress = progress
        }
        
        return outputURL
    }
    
    // MARK: - Persistence
    
    /// Saves chains to disk, capturing current plugin states
    /// Set skipCapture to true when states are already up to date (e.g., during processing)
    func saveChains(skipCapture: Bool = false) {
        // Skip during training to avoid AU reload spam
        guard !NAMTrainer.shared.isTraining else {
            // Just save without capturing during training
            do {
                let data = try JSONEncoder().encode(chains)
                try data.write(to: chainsFileURL)
            } catch {
                print("Failed to save chains: \(error)")
            }
            return
        }
        
        // Capture current plugin states from the audio engine before saving
        if !skipCapture {
            captureCurrentChainState()
        }
        
        do {
            let data = try JSONEncoder().encode(chains)
            try data.write(to: chainsFileURL)
            print("Saved \(chains.count) chains to disk")
        } catch {
            print("Failed to save chains: \(error)")
        }
    }
    
    /// Captures the current plugin states from AudioEngine and updates the selected chain
    func captureCurrentChainState() {
        guard let selectedIndex = chains.firstIndex(where: { $0.id == selectedChain?.id }) else { return }
        
        // Get updated chain with plugin states from AudioEngine
        if let updatedChain = AudioEngine.shared.updateChainWithPluginStates() {
            chains[selectedIndex] = updatedChain
            selectedChain = updatedChain
            print("Captured plugin states for chain: \(updatedChain.name)")
        }
    }
    
    /// Loads chains from disk
    func loadChains() {
        guard FileManager.default.fileExists(atPath: chainsFileURL.path) else {
            // Create sample chains for first run
            chains = ProcessingChain.sampleList
            return
        }
        
        do {
            let data = try Data(contentsOf: chainsFileURL)
            chains = try JSONDecoder().decode([ProcessingChain].self, from: data)
        } catch {
            print("Failed to load chains: \(error)")
            chains = []
        }
    }
    
    /// Exports a chain preset
    func exportChain(_ chain: ProcessingChain, to url: URL) throws {
        let data = try JSONEncoder().encode(chain)
        try data.write(to: url)
    }
    
    /// Imports a chain preset
    func importChain(from url: URL) throws {
        let data = try Data(contentsOf: url)
        var chain = try JSONDecoder().decode(ProcessingChain.self, from: data)
        // Give it a new ID to avoid conflicts
        chain = ProcessingChain(
            name: chain.name,
            isEnabled: chain.isEnabled,
            plugins: chain.plugins
        )
        chains.append(chain)
        selectedChainId = chain.id
    }
    
    // MARK: - Private Methods
    
    private func setupAutoSave() {
        // Auto-save when chains change (but not during training or processing)
        $chains
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                
                // Skip auto-save during training or processing to prevent AU reloading spam
                guard !NAMTrainer.shared.isTraining else { return }
                guard !self.isProcessing else { return }
                
                if AppSettings.shared.autoSaveChains {
                    self.saveChains()
                }
            }
            .store(in: &cancellables)
    }
}

// MARK: - Errors

enum ChainError: LocalizedError {
    case noInputFile
    case noChainsEnabled
    case processingFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .noInputFile:
            return "No input file selected"
        case .noChainsEnabled:
            return "No chains are enabled for processing"
        case .processingFailed(let reason):
            return "Processing failed: \(reason)"
        }
    }
}
