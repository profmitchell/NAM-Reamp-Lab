//
//  PluginRowView.swift
//  NAM Reamp Lab
//

import SwiftUI
import AppKit

struct PluginRowView: View {
    let plugin: AudioPlugin
    let index: Int
    let onToggle: () -> Void
    let onBypass: () -> Void
    let onRemove: () -> Void
    var onFavorite: (() -> Void)? = nil
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
                    Text(plugin.type.name)
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
            
            // Favorite button
            if let onFavorite = onFavorite {
                Button {
                    onFavorite()
                } label: {
                    Image(systemName: plugin.isFavorite ? "star.fill" : "star")
                        .foregroundColor(plugin.isFavorite ? .yellow : .secondary)
                }
                .buttonStyle(.borderless)
                .help(plugin.isFavorite ? "Remove from favorites" : "Add to favorites")
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
