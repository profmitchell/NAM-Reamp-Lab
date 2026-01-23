//
//  PluginUIHostView.swift
//  NAM Reamp Lab
//

import SwiftUI
import AVFoundation
import CoreAudioKit
import AppKit

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
        
        await MainActor.run {
            isLoading = false
        }
    }
}

struct AudioUnitViewRepresentable: NSViewControllerRepresentable {
    let viewController: NSViewController
    
    func makeNSViewController(context: Context) -> NSViewController {
        return viewController
    }
    
    func updateNSViewController(_ nsViewController: NSViewController, context: Context) {
        // No updates needed
    }
}
