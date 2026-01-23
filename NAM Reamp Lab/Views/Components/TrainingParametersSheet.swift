//
//  TrainingParametersSheet.swift
//  NAM Reamp Lab
//

import SwiftUI

struct TrainingParametersSheet: View {
    @Binding var parameters: TrainingParameters
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var pythonManager = PythonManager.shared
    
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
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            
            Divider()
            
            Form {
                Section("Model Configuration") {
                    Picker("Architecture", selection: $parameters.architecture) {
                        ForEach(ModelArchitecture.allCases, id: \.self) { arch in
                            Text(arch.rawValue).tag(arch)
                        }
                    }
                    
                    if parameters.architecture == .wavenet {
                        Picker("Size Preset", selection: Binding(
                            get: { parameters.preset ?? .full },
                            set: { parameters.preset = $0 }
                        )) {
                            ForEach(TrainingPreset.allCases, id: \.self) { preset in
                                VStack(alignment: .leading) {
                                    Text(preset.rawValue)
                                    Text(preset.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .tag(preset)
                            }
                        }
                    }
                }
                
                Section("Training Hyperparameters") {
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
