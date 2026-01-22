//
//  NAM_Reamp_LabApp.swift
//  NAM Reamp Lab
//
//  Created by Mitchell Cohen on 1/22/26.
//

import SwiftUI
import UniformTypeIdentifiers

@main
struct NAM_Reamp_LabApp: App {
    @StateObject private var appSettings = AppSettings.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appSettings)
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            // File menu commands
            CommandGroup(after: .newItem) {
                Divider()
                
                Button("Open Input File...") {
                    openInputFile()
                }
                .keyboardShortcut("o", modifiers: .command)
                
                Menu("Recent Files") {
                    ForEach(appSettings.recentInputFiles, id: \.self) { path in
                        Button(URL(fileURLWithPath: path).lastPathComponent) {
                            ChainManager.shared.inputFileURL = URL(fileURLWithPath: path)
                        }
                    }
                    
                    if !appSettings.recentInputFiles.isEmpty {
                        Divider()
                        Button("Clear Recent") {
                            appSettings.clearRecentFiles()
                        }
                    }
                }
            }
            
            // Chain menu
            CommandMenu("Chain") {
                Button("New Chain") {
                    ChainManager.shared.createChain()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                
                Button("Duplicate Chain") {
                    if let chain = ChainManager.shared.selectedChain {
                        ChainManager.shared.duplicateChain(chain)
                    }
                }
                .keyboardShortcut("d", modifiers: .command)
                
                Divider()
                
                Button("Process All Chains") {
                    processAllChains()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            }
            
            // Training menu
            CommandMenu("Training") {
                Button("Train All Pending") {
                    trainAllPending()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                
                Button("Cancel Training") {
                    NAMTrainer.shared.cancelCurrentTraining()
                }
                .keyboardShortcut(".", modifiers: .command)
                
                Divider()
                
                Button("Clear Completed Jobs") {
                    NAMTrainer.shared.clearCompletedJobs()
                }
            }
            
            // Help menu
            CommandGroup(replacing: .help) {
                Link("NAM Documentation", destination: URL(string: "https://github.com/sdatkinson/neural-amp-modeler")!)
                Link("Report an Issue", destination: URL(string: "https://github.com/sdatkinson/neural-amp-modeler/issues")!)
            }
        }
        
        // Settings window
        Settings {
            SettingsView()
        }
    }
    
    // MARK: - Helper Functions
    
    private func openInputFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .wav, .aiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Select an input audio file (DI recording)"
        
        if panel.runModal() == .OK, let url = panel.url {
            ChainManager.shared.inputFileURL = url
            appSettings.addRecentInputFile(url.path)
        }
    }
    
    private func processAllChains() {
        Task {
            let outputFolder = URL(fileURLWithPath: appSettings.defaultOutputFolder)
            do {
                _ = try await ChainManager.shared.processAllEnabledChains(outputFolder: outputFolder)
            } catch {
                print("Processing error: \(error)")
            }
        }
    }
    
    private func trainAllPending() {
        Task {
            do {
                try await NAMTrainer.shared.trainAllPending()
            } catch {
                print("Training error: \(error)")
            }
        }
    }
}
