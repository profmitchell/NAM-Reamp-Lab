//
//  TrainingView.swift
//  NAM Reamp Lab
//
//  Created by Mitchell Cohen on 1/22/26.
//

import SwiftUI
import UniformTypeIdentifiers

/// Main view for Tab 2 - Model Training
struct TrainingView: View {
    @StateObject private var trainer = NAMTrainer.shared
    @StateObject private var pythonManager = PythonManager.shared
    @StateObject private var chainManager = ChainManager.shared
    
    @State private var showingInputFilePicker = false
    @State private var showingOutputFilesPicker = false
    @State private var showingParametersSheet = false
    @State private var selectedJobIds: Set<UUID> = []
    @State private var trainingError: String?
    @State private var showingError = false
    @State private var showingCompletionDialog = false
    @State private var completedJob: TrainingJob?
    
    var body: some View {
        HSplitView {
            // Left side - Job list and controls
            jobListView
                .frame(minWidth: 300, idealWidth: 400)
            
            // Right side - Job details and log
            jobDetailView
                .frame(minWidth: 400)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                toolbarItems
            }
        }
        .sheet(isPresented: $showingParametersSheet) {
            TrainingParametersSheet(parameters: $trainer.parameters)
        }
        .fileImporter(
            isPresented: $showingOutputFilesPicker,
            allowedContentTypes: [.audio, .wav, .aiff],
            allowsMultipleSelection: true
        ) { result in
            handleOutputFilesSelection(result)
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(trainingError ?? "Unknown error")
        }
        .sheet(isPresented: $showingCompletionDialog) {
            if let job = completedJob {
                TrainingCompletionSheet(job: job) {
                    showingCompletionDialog = false
                    completedJob = nil
                    trainer.lastCompletedJob = nil
                }
            }
        }
        .onChange(of: trainer.lastCompletedJob) { oldValue, newValue in
            print("📋 lastCompletedJob changed: \(oldValue?.chainName ?? "nil") -> \(newValue?.chainName ?? "nil")")
            if let job = newValue {
                print("📋 Setting completedJob and showing dialog")
                completedJob = job
                showingCompletionDialog = true
            }
        }
        .task {
            // Initialize Python on view appear
            if !pythonManager.status.isReady {
                await pythonManager.initialize()
            }
        }
    }
    
    // MARK: - Job List View
    
    private var jobListView: some View {
        VStack(spacing: 0) {
            // Python status
            pythonStatusBanner
            
            // Input file section
            inputSection
            
            Divider()
            
            // Job list
            if trainer.jobs.isEmpty {
                emptyJobsView
            } else {
                jobsList
            }
            
            Divider()
            
            // Actions
            jobListActions
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var pythonStatusBanner: some View {
        Group {
            if !pythonManager.status.isReady {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        switch pythonManager.status {
                        case .initializing:
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Initializing Python...")
                        case .error(_):
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                            Text("Training Setup Required")
                                .fontWeight(.medium)
                        default:
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                            Text("Training Setup Required")
                        }
                        Spacer()
                    }
                    
                    if case .error = pythonManager.status {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("To train NAM models, you need:")
                                .font(.caption)
                            Text("• Python 3.9+ with pip")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("• pip install neural-amp-modeler")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("• pip install torch")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(8)
                .background(Color.blue.opacity(0.1))
            }
        }
    }
    
    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Use same input file as Chain Builder
            if let inputURL = chainManager.inputFileURL {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Input File (DI)")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Image(systemName: "waveform")
                            .foregroundColor(.accentColor)
                        Text(inputURL.lastPathComponent)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                }
            } else {
                Text("Set input file in Chain Builder tab")
                    .foregroundColor(.secondary)
            }
            
            // Add output files button
            Button {
                showingOutputFilesPicker = true
            } label: {
                Label("Add Output Files to Train", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(chainManager.inputFileURL == nil)
        }
        .padding()
    }
    
    private var emptyJobsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "brain")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No Training Jobs")
                .font(.title3)
                .foregroundColor(.secondary)
            
            Text("Add output files to create training jobs, or process chains first in the Chain Builder tab")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var jobsList: some View {
        List(selection: $selectedJobIds) {
            ForEach(trainer.jobs) { job in
                TrainingJobRowView(job: job)
                    .tag(job.id)
                    .contextMenu {
                        jobContextMenu(for: job)
                    }
            }
        }
        .listStyle(.inset)
    }
    
    private var jobListActions: some View {
        HStack {
            // Progress for overall training
            if trainer.isTraining {
                VStack(alignment: .leading, spacing: 2) {
                    ProgressView(value: trainer.overallProgress)
                        .frame(width: 100)
                    Text("Training...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Button {
                trainer.clearCompletedJobs()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(trainer.jobs.filter { $0.status == .completed || $0.status == .failed }.isEmpty)
            .help("Clear completed jobs")
        }
        .padding(8)
    }
    
    @ViewBuilder
    private func jobContextMenu(for job: TrainingJob) -> some View {
        if job.status == .pending {
            Button {
                Task {
                    try? await trainer.trainSingle(job)
                }
            } label: {
                Label("Train Now", systemImage: "play.fill")
            }
        }
        
        if job.status == .running {
            Button {
                trainer.cancelCurrentTraining()
            } label: {
                Label("Cancel", systemImage: "stop.fill")
            }
        }
        
        if job.status == .completed, let modelPath = job.modelOutputPath {
            Button {
                NSWorkspace.shared.selectFile(modelPath, inFileViewerRootedAtPath: "")
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }
        }
        
        Divider()
        
        Button(role: .destructive) {
            trainer.removeJob(job)
        } label: {
            Label("Remove", systemImage: "trash")
        }
    }
    
    // MARK: - Job Detail View
    
    @ViewBuilder
    private var jobDetailView: some View {
        if let selectedId = selectedJobIds.first,
           let job = trainer.jobs.first(where: { $0.id == selectedId }) {
            TrainingJobDetailView(job: job)
        } else if let currentJob = trainer.currentJob {
            TrainingJobDetailView(job: currentJob)
        } else {
            emptyDetailView
        }
    }
    
    private var emptyDetailView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            Text("Select a Training Job")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text("Select a job from the list to see its details and training log")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Toolbar
    
    @ViewBuilder
    private var toolbarItems: some View {
        Button {
            showingParametersSheet = true
        } label: {
            Label("Parameters", systemImage: "slider.horizontal.3")
        }
        
        if trainer.isTraining {
            Button {
                trainer.cancelCurrentTraining()
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .tint(.red)
        } else {
            Button {
                Task {
                    do {
                        try await trainer.trainAllPending()
                    } catch {
                        trainingError = error.localizedDescription
                        showingError = true
                    }
                }
            } label: {
                Label("Train All", systemImage: "play.fill")
            }
            .disabled(!pythonManager.status.isReady || trainer.jobs.filter { $0.status == .pending }.isEmpty)
        }
    }
    
    // MARK: - Helpers
    
    private func handleOutputFilesSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let inputURL = chainManager.inputFileURL else { return }
            _ = trainer.createJobsFromOutputFiles(urls, inputFile: inputURL)
        case .failure(let error):
            trainingError = error.localizedDescription
            showingError = true
        }
    }
}

#Preview {
    TrainingView()
}
