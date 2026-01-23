//
//  TrainingCompletionSheet.swift
//  NAM Reamp Lab
//

import SwiftUI
import AppKit

struct TrainingCompletionSheet: View {
    let job: TrainingJob
    let onDismiss: () -> Void
    
    @State private var newModelName: String = ""
    @State private var hasRenamed = false
    
    var modelFileName: String {
        guard let path = job.modelOutputPath else { return "model.nam" }
        return URL(fileURLWithPath: path).lastPathComponent
    }
    
    var modelFolder: String {
        guard let path = job.modelOutputPath else { return "" }
        return URL(fileURLWithPath: path).deletingLastPathComponent().path
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Success icon
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)
            
            Text("Training Complete!")
                .font(.title)
                .fontWeight(.bold)
            
            if let chainName = job.chainName {
                Text("Model trained for: \(chainName)")
                    .foregroundColor(.secondary)
            }
            
            // Model path info
            VStack(alignment: .leading, spacing: 8) {
                Text("Model saved to:")
                    .font(.headline)
                
                if let path = job.modelOutputPath {
                    Text(path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                        .padding(8)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            // Rename section
            VStack(alignment: .leading, spacing: 8) {
                Text("Rename Model (optional)")
                    .font(.headline)
                
                HStack {
                    TextField("New name", text: $newModelName)
                        .textFieldStyle(.roundedBorder)
                    
                    Text(".nam")
                        .foregroundColor(.secondary)
                    
                    Button("Rename") {
                        renameModel()
                    }
                    .disabled(newModelName.isEmpty || hasRenamed)
                }
                
                if hasRenamed {
                    Label("Model renamed successfully!", systemImage: "checkmark")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            Spacer()
            
            // Actions
            HStack(spacing: 16) {
                Button {
                    onDismiss()
                } label: {
                    Text("Close")
                        .frame(width: 100)
                }
                .buttonStyle(.bordered)
                
                Button {
                    openInFinder()
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                        .frame(width: 150)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(30)
        .frame(width: 500, height: 450)
        .onAppear {
            // Suggest a name based on chain name
            if let chainName = job.chainName {
                newModelName = chainName.replacingOccurrences(of: " ", with: "_")
            }
        }
    }
    
    private func openInFinder() {
        guard let path = job.modelOutputPath else { 
            print("⚠️ No model output path")
            return 
        }
        
        let url = URL(fileURLWithPath: path)
        let fm = FileManager.default
        
        if fm.fileExists(atPath: path) {
            // File exists - select it in Finder
            NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
        } else {
            // File doesn't exist - open the parent folder
            let folder = url.deletingLastPathComponent()
            if fm.fileExists(atPath: folder.path) {
                NSWorkspace.shared.open(folder)
            } else {
                print("⚠️ Neither file nor folder exists: \(path)")
            }
        }
    }
    
    private func renameModel() {
        guard let oldPath = job.modelOutputPath, !newModelName.isEmpty else { return }
        
        let oldURL = URL(fileURLWithPath: oldPath)
        let newURL = oldURL.deletingLastPathComponent().appendingPathComponent("\(newModelName).nam")
        
        do {
            try FileManager.default.moveItem(at: oldURL, to: newURL)
            hasRenamed = true
        } catch {
            print("Failed to rename model: \(error)")
        }
    }
}
