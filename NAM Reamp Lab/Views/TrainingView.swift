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

// MARK: - Training Job Row View

struct TrainingJobRowView: View {
    let job: TrainingJob
    
    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            statusIcon
            
            // Job info
            VStack(alignment: .leading, spacing: 2) {
                Text(job.displayName)
                    .fontWeight(.medium)
                
                HStack(spacing: 8) {
                    Text(job.status.rawValue)
                        .font(.caption)
                        .foregroundColor(statusColor)
                    
                    if job.status == .running {
                        Text("Epoch \(job.currentEpoch)/\(job.totalEpochs)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let duration = job.formattedDuration {
                        Text(duration)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Progress or status indicator
            if job.status == .running {
                VStack(alignment: .trailing, spacing: 2) {
                    ProgressView(value: job.progress)
                        .frame(width: 80)
                    Text("\(Int(job.progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if let loss = job.currentLoss {
                Text("Loss: \(String(format: "%.4f", loss))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
    }
    
    private var statusIcon: some View {
        Group {
            switch job.status {
            case .pending:
                Image(systemName: "clock")
                    .foregroundColor(.secondary)
            case .running:
                ProgressView()
                    .scaleEffect(0.7)
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            case .cancelled:
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.orange)
            }
        }
        .frame(width: 24)
    }
    
    private var statusColor: Color {
        switch job.status {
        case .pending: return .secondary
        case .running: return .blue
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .orange
        }
    }
}

// MARK: - Training Job Detail View

struct TrainingJobDetailView: View {
    let job: TrainingJob
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            jobHeader
            
            Divider()
            
            // Stats grid
            statsGrid
            
            Divider()
            
            // Log output
            logView
        }
    }
    
    private var jobHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(job.displayName)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                statusBadge
            }
            
            if let error = job.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
        .padding()
    }
    
    private var statusBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: job.status.icon)
            Text(job.status.rawValue)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusBackgroundColor)
        .foregroundColor(statusForegroundColor)
        .cornerRadius(6)
    }
    
    private var statusBackgroundColor: Color {
        switch job.status {
        case .pending: return Color.secondary.opacity(0.2)
        case .running: return Color.blue.opacity(0.2)
        case .completed: return Color.green.opacity(0.2)
        case .failed: return Color.red.opacity(0.2)
        case .cancelled: return Color.orange.opacity(0.2)
        }
    }
    
    private var statusForegroundColor: Color {
        switch job.status {
        case .pending: return .secondary
        case .running: return .blue
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .orange
        }
    }
    
    private var statsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            StatView(title: "Epoch", value: "\(job.currentEpoch)/\(job.totalEpochs)")
            StatView(title: "Progress", value: "\(Int(job.progress * 100))%")
            StatView(title: "Loss", value: job.currentLoss.map { String(format: "%.4f", $0) } ?? "-")
            StatView(title: "Duration", value: job.formattedDuration ?? "-")
        }
        .padding()
    }
    
    private var logView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Training Log")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(job.logOutput, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(job.logOutput.isEmpty)
            }
            
            ScrollView {
                ScrollViewReader { proxy in
                    Text(job.logOutput.isEmpty ? "No output yet..." : job.logOutput)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)  // Make text selectable
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("logBottom")
                        .onChange(of: job.logOutput) { _, _ in
                            withAnimation {
                                proxy.scrollTo("logBottom", anchor: .bottom)
                            }
                        }
                }
            }
            .padding(8)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)
        }
        .padding()
    }
}

// MARK: - Stat View

struct StatView: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .monospacedDigit()
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Training Parameters Sheet

struct TrainingParametersSheet: View {
    @Binding var parameters: TrainingParameters
    @Environment(\.dismiss) private var dismiss
    @StateObject private var pythonManager = PythonManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Training Parameters")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Done") {
                    dismiss()
                }
            }
            .padding()
            
            Divider()
            
            Form {
                // Architecture
                Section("Model Architecture") {
                    Picker("Architecture", selection: $parameters.architecture) {
                        ForEach(ModelArchitecture.allCases, id: \.self) { arch in
                            Text(arch.rawValue).tag(arch)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    Text(parameters.architecture.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Training settings
                Section("Training Settings") {
                    HStack {
                        Text("Epochs")
                        Spacer()
                        TextField("Epochs", value: $parameters.epochs, format: .number)
                            .frame(width: 80)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    HStack {
                        Text("Learning Rate")
                        Spacer()
                        TextField("Learning Rate", value: $parameters.learningRate, format: .number)
                            .frame(width: 100)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    HStack {
                        Text("Batch Size")
                        Spacer()
                        TextField("Batch Size", value: $parameters.batchSize, format: .number)
                            .frame(width: 80)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    HStack {
                        Text("Validation Split")
                        Spacer()
                        TextField("Validation Split", value: $parameters.validationSplit, format: .number)
                            .frame(width: 80)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                
                // Early stopping
                Section("Early Stopping") {
                    Toggle("Enable Early Stopping", isOn: $parameters.earlyStopping)
                    
                    if parameters.earlyStopping {
                        HStack {
                            Text("Patience")
                            Spacer()
                            TextField("Patience", value: $parameters.patience, format: .number)
                                .frame(width: 80)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                
                // Environment info
                Section("Environment") {
                    LabeledContent("Python Version", value: pythonManager.pythonVersion)
                    LabeledContent("PyTorch Version", value: pythonManager.torchVersion)
                    LabeledContent("NAM Version", value: pythonManager.namVersion)
                    LabeledContent("GPU Available", value: pythonManager.hasMPS ? "Yes (MPS)" : "No")
                }
                
                // Presets
                Section("Presets") {
                    HStack {
                        Button("Quick (25 epochs)") {
                            parameters = .quick
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Default (100 epochs)") {
                            parameters = .default
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Full (250 epochs)") {
                            parameters = .full
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 500, height: 600)
    }
}

// MARK: - Preview

#Preview {
    TrainingView()
}
