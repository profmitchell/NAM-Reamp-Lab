//
//  ContentView.swift
//  NAM Reamp Lab
//
//  Created by Mitchell Cohen on 1/22/26.
//

import SwiftUI

/// Main content view with tab navigation
struct ContentView: View {
    @State private var selectedTab = 0
    @StateObject private var chainManager = ChainManager.shared
    @StateObject private var pythonManager = PythonManager.shared
    @StateObject private var audioUnitManager = AudioUnitHostManager.shared
    @StateObject private var trainer = NAMTrainer.shared
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: Chain Builder
            ChainBuilderView()
                .tabItem {
                    Label("Chain Builder", systemImage: "link")
                }
                .tag(0)
            
            // Tab 2: Training
            TrainingView()
                .tabItem {
                    Label("Training", systemImage: "brain")
                }
                .tag(1)
            
            // Tab 3: Settings
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(2)
        }
        .frame(minWidth: 1000, minHeight: 700)
        .task {
            // Defer initialization to avoid "publishing changes during view updates" warning
            try? await Task.sleep(for: .milliseconds(100))
            await initializeApp()
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToTrainingTab)) { _ in
            withAnimation {
                selectedTab = 1
            }
        }
    }
    
    private func initializeApp() async {
        // Initialize Python environment
        await pythonManager.initialize()
        
        // Scan for Audio Units
        await audioUnitManager.scanForAudioUnits()
        
        // Create required directories
        await MainActor.run {
            AppSettings.shared.createRequiredDirectories()
        }
    }
}

#Preview {
    ContentView()
}
