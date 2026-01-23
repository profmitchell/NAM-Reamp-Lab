//
//  ModelNamingSheet.swift
//  NAM Reamp Lab
//

import SwiftUI
import AppKit

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
