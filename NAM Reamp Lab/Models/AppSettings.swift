//
//  AppSettings.swift
//  NAM Reamp Lab
//
//  Created by Mitchell Cohen on 1/22/26.
//

import Foundation
import Combine

/// App-wide settings stored in UserDefaults
class AppSettings: ObservableObject {
    static let shared = AppSettings()
    
    private let defaults = UserDefaults.standard
    
    // MARK: - Keys
    
    private enum Keys {
        static let pythonPath = "pythonPath"
        static let namPackagePath = "namPackagePath"
        static let defaultOutputFolder = "defaultOutputFolder"
        static let defaultModelFolder = "defaultModelFolder"
        static let defaultIRFolder = "defaultIRFolder"
        static let trainingEpochs = "trainingEpochs"
        static let trainingArchitecture = "trainingArchitecture"
        static let useBundledPython = "useBundledPython"
        static let autoSaveChains = "autoSaveChains"
        static let previewBufferSize = "previewBufferSize"
        static let recentInputFiles = "recentInputFiles"
        static let lastUsedChainId = "lastUsedChainId"
    }
    
    // MARK: - Python Settings
    
    @Published var pythonPath: String {
        didSet { defaults.set(pythonPath, forKey: Keys.pythonPath) }
    }
    
    @Published var namPackagePath: String {
        didSet { defaults.set(namPackagePath, forKey: Keys.namPackagePath) }
    }
    
    @Published var useBundledPython: Bool {
        didSet { defaults.set(useBundledPython, forKey: Keys.useBundledPython) }
    }
    
    // MARK: - Folder Settings
    
    @Published var defaultOutputFolder: String {
        didSet { defaults.set(defaultOutputFolder, forKey: Keys.defaultOutputFolder) }
    }
    
    @Published var defaultModelFolder: String {
        didSet { defaults.set(defaultModelFolder, forKey: Keys.defaultModelFolder) }
    }
    
    @Published var defaultIRFolder: String {
        didSet { defaults.set(defaultIRFolder, forKey: Keys.defaultIRFolder) }
    }
    
    // MARK: - Training Settings
    
    @Published var trainingEpochs: Int {
        didSet { defaults.set(trainingEpochs, forKey: Keys.trainingEpochs) }
    }
    
    @Published var trainingArchitecture: ModelArchitecture {
        didSet { defaults.set(trainingArchitecture.rawValue, forKey: Keys.trainingArchitecture) }
    }
    
    // MARK: - App Behavior
    
    @Published var autoSaveChains: Bool {
        didSet { defaults.set(autoSaveChains, forKey: Keys.autoSaveChains) }
    }
    
    @Published var previewBufferSize: Int {
        didSet { defaults.set(previewBufferSize, forKey: Keys.previewBufferSize) }
    }
    
    // MARK: - Recent Files
    
    @Published var recentInputFiles: [String] {
        didSet { defaults.set(recentInputFiles, forKey: Keys.recentInputFiles) }
    }
    
    @Published var lastUsedChainId: String? {
        didSet { defaults.set(lastUsedChainId, forKey: Keys.lastUsedChainId) }
    }
    
    // MARK: - Initialization
    
    private init() {
        let defaults = UserDefaults.standard
        
        // Python settings - try to find a good default
        let defaultPythonPath: String
        let venvPath = "/Users/Shared/CohenConcepts/NAM Reamp Lab/.venv/bin/python"
        let homebrewPath = "/opt/homebrew/bin/python3"
        let systemPath = "/usr/bin/python3"
        
        if FileManager.default.fileExists(atPath: venvPath) {
            defaultPythonPath = venvPath
        } else if FileManager.default.fileExists(atPath: homebrewPath) {
            defaultPythonPath = homebrewPath
        } else {
            defaultPythonPath = systemPath
        }
        
        self.pythonPath = defaults.string(forKey: Keys.pythonPath) ?? defaultPythonPath
        
        // NAM package path - leave empty since NAM is installed in the venv
        // Setting this would cause Python to import from the raw folder instead of installed package
        self.namPackagePath = defaults.string(forKey: Keys.namPackagePath) ?? ""
        
        self.useBundledPython = defaults.bool(forKey: Keys.useBundledPython)
        
        // Folder settings
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path ?? ""
        self.defaultOutputFolder = defaults.string(forKey: Keys.defaultOutputFolder) ?? "\(documentsPath)/NAM Reamp Lab/Output"
        self.defaultModelFolder = defaults.string(forKey: Keys.defaultModelFolder) ?? "\(documentsPath)/NAM Reamp Lab/Models"
        self.defaultIRFolder = defaults.string(forKey: Keys.defaultIRFolder) ?? "\(documentsPath)/NAM Reamp Lab/IRs"
        
        // Training settings - use local variables first
        let savedEpochs = defaults.integer(forKey: Keys.trainingEpochs)
        self.trainingEpochs = savedEpochs == 0 ? 100 : savedEpochs
        
        let archString = defaults.string(forKey: Keys.trainingArchitecture) ?? ModelArchitecture.wavenet.rawValue
        self.trainingArchitecture = ModelArchitecture(rawValue: archString) ?? .wavenet
        
        // App behavior - use local variables first
        self.autoSaveChains = defaults.object(forKey: Keys.autoSaveChains) as? Bool ?? true
        
        let savedBufferSize = defaults.integer(forKey: Keys.previewBufferSize)
        self.previewBufferSize = savedBufferSize == 0 ? 512 : savedBufferSize
        
        // Recent files - must initialize before using self
        self.recentInputFiles = defaults.stringArray(forKey: Keys.recentInputFiles) ?? []
        self.lastUsedChainId = defaults.string(forKey: Keys.lastUsedChainId)
    }
    
    // MARK: - Methods
    
    /// Adds a file to recent input files
    func addRecentInputFile(_ path: String) {
        var files = recentInputFiles.filter { $0 != path }
        files.insert(path, at: 0)
        if files.count > 10 {
            files = Array(files.prefix(10))
        }
        recentInputFiles = files
    }
    
    /// Clears all recent files
    func clearRecentFiles() {
        recentInputFiles = []
    }
    
    /// Resets all settings to defaults
    func resetToDefaults() {
        pythonPath = "/usr/bin/python3"
        namPackagePath = ""
        useBundledPython = false
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path ?? ""
        defaultOutputFolder = "\(documentsPath)/NAM Reamp Lab/Output"
        defaultModelFolder = "\(documentsPath)/NAM Reamp Lab/Models"
        defaultIRFolder = "\(documentsPath)/NAM Reamp Lab/IRs"
        
        trainingEpochs = 100
        trainingArchitecture = .wavenet
        autoSaveChains = true
        previewBufferSize = 512
    }
    
    /// Creates required directories
    func createRequiredDirectories() {
        let fm = FileManager.default
        let folders = [defaultOutputFolder, defaultModelFolder, defaultIRFolder]
        
        for folder in folders {
            if !fm.fileExists(atPath: folder) {
                try? fm.createDirectory(atPath: folder, withIntermediateDirectories: true)
            }
        }
    }
}
