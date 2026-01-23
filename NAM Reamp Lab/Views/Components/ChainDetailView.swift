//
//  ChainDetailView.swift
//  NAM Reamp Lab
//

import SwiftUI

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
                    onRemove: { chainManager.removePlugin(plugin, from: chain) },
                    onFavorite: { chainManager.toggleFavorite(plugin, in: chain) }
                )
            }
            .onMove { source, destination in
                chainManager.movePlugins(in: chain, from: source, to: destination)
            }
        }
    }
}
