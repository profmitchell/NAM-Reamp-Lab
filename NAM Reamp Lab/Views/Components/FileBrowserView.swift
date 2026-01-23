//
//  FileBrowserView.swift
//  NAM Reamp Lab
//

import SwiftUI

struct FileBrowserItem: Identifiable {
    let id = UUID()
    let url: URL
    let isDirectory: Bool
    
    var name: String { url.lastPathComponent }
    var icon: String { isDirectory ? "folder.fill" : "filemenu.and.selection" }
}

struct FileBrowserView: View {
    let rootURL: URL
    let fileExtension: String
    let onSelect: (URL) -> Void
    
    @State private var currentURL: URL
    @State private var items: [FileBrowserItem] = []
    @State private var breadcrumbs: [URL] = []
    
    init(rootURL: URL, fileExtension: String, onSelect: @escaping (URL) -> Void) {
        self.rootURL = rootURL
        self.fileExtension = fileExtension
        self.onSelect = onSelect
        _currentURL = State(initialValue: rootURL)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Navigation Bar
            HStack {
                Button {
                    goUp()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(currentURL.path == rootURL.path)
                .buttonStyle(.borderless)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(breadcrumbs, id: \.self) { url in
                            Button(url == rootURL ? "Root" : url.lastPathComponent) {
                                navigateTo(url)
                            }
                            .buttonStyle(.borderless)
                            .foregroundColor(.accentColor)
                            
                            if url != breadcrumbs.last {
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Spacer()
                
                Button {
                    loadItems()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // File List
            List {
                ForEach(items) { item in
                    HStack {
                        Image(systemName: item.icon)
                            .foregroundColor(item.isDirectory ? .accentColor : .secondary)
                        
                        Text(item.name)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        if !item.isDirectory {
                            Button("Add") {
                                onSelect(item.url)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if item.isDirectory {
                            navigateTo(item.url)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        .onAppear {
            loadItems()
            updateBreadcrumbs()
        }
    }
    
    private func loadItems() {
        let fileManager = FileManager.default
        do {
            let resourceKeys: [URLResourceKey] = [.isDirectoryKey]
            let contents = try fileManager.contentsOfDirectory(at: currentURL, includingPropertiesForKeys: resourceKeys, options: [.skipsHiddenFiles])
            
            items = contents.compactMap { url -> FileBrowserItem? in
                let resourceValues = try? url.resourceValues(forKeys: Set(resourceKeys))
                let isDir = resourceValues?.isDirectory ?? false
                
                if isDir {
                    return FileBrowserItem(url: url, isDirectory: true)
                } else if url.pathExtension.lowercased() == fileExtension.lowercased() {
                    return FileBrowserItem(url: url, isDirectory: false)
                }
                return nil
            }.sorted { (a, b) in
                if a.isDirectory != b.isDirectory {
                    return a.isDirectory
                }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        } catch {
            print("Failed to load directory contents: \(error)")
            items = []
        }
    }
    
    private func navigateTo(_ url: URL) {
        currentURL = url
        loadItems()
        updateBreadcrumbs()
    }
    
    private func goUp() {
        if currentURL.path != rootURL.path {
            navigateTo(currentURL.deletingLastPathComponent())
        }
    }
    
    private func updateBreadcrumbs() {
        var path = currentURL
        var newBreadcrumbs: [URL] = []
        
        while path.path.hasPrefix(rootURL.path) {
            newBreadcrumbs.insert(path, at: 0)
            if path.path == rootURL.path { break }
            path = path.deletingLastPathComponent()
        }
        
        breadcrumbs = newBreadcrumbs
    }
}
