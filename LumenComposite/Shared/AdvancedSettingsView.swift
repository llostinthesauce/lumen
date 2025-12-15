import SwiftUI

struct AdvancedSettingsView: View {
    @ObservedObject var state: AppState
    @Binding var modelFolders: [String]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                Text("Model Configuration")
                    .font(.title2)
                    .fontWeight(.bold)
                
                // Generation Parameters
                if let thread = state.selectedThread {
                    GroupBox(label: Label("Generation Parameters", systemImage: "slider.horizontal.3")) {
                        VStack(alignment: .leading, spacing: 16) {
                            // Temperature
                            VStack(alignment: .leading) {
                                HStack {
                                    Text("Temperature")
                                    Spacer()
                                    Text(String(format: "%.2f", thread.config.temperature))
                                        .foregroundStyle(.secondary)
                                }
                                Slider(value: Binding(
                                    get: { thread.config.temperature },
                                    set: { val in state.updateSelected { $0.config.temperature = val } }
                                ), in: 0...2)
                                Text("Controls randomness: Higher values (e.g. 1.0) make output more random, lower values (e.g. 0.2) make it more deterministic.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            // Top P
                            VStack(alignment: .leading) {
                                HStack {
                                    Text("Top P")
                                    Spacer()
                                    Text(String(format: "%.2f", thread.config.topP))
                                        .foregroundStyle(.secondary)
                                }
                                Slider(value: Binding(
                                    get: { thread.config.topP },
                                    set: { val in state.updateSelected { $0.config.topP = val } }
                                ), in: 0...1)
                            }
                            
                            // Max Tokens
                            VStack(alignment: .leading) {
                                HStack {
                                    Text("Max Tokens")
                                    Spacer()
                                    Text("\(thread.config.maxTokens)")
                                        .foregroundStyle(.secondary)
                                }
                                Slider(value: Binding(
                                    get: { Double(thread.config.maxTokens) },
                                    set: { val in state.updateSelected { $0.config.maxTokens = Int(val) } }
                                ), in: 128...8192, step: 128)
                            }
                            
                            // System Prompt
                            VStack(alignment: .leading) {
                                Text("System Prompt")
                                TextEditor(text: Binding(
                                    get: { thread.config.systemPrompt },
                                    set: { val in state.updateSelected { $0.config.systemPrompt = val } }
                                ))
                                .font(.system(.body, design: .monospaced))
                                .frame(height: 100)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                            }
                        }
                        .padding(8)
                    }
                } else {
                    Text("Select a chat to configure parameters.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }
    
    // MARK: - Actions
    
    private func applyModelDefaults(for modelId: String) {
        guard let defaults = ModelDefaultsRegistry.shared.config(for: modelId) else { return }
        
        state.updateSelected { thread in
            thread.config.temperature = defaults.temperature
            thread.config.topP = defaults.topP
            thread.config.maxTokens = defaults.maxTokens
            thread.config.maxKV = defaults.maxKV
            if !defaults.systemPrompt.isEmpty {
                thread.config.systemPrompt = defaults.systemPrompt
            }
        }
    }
    
    private func resetToDefaults() {
        guard let modelId = state.selectedThread?.modelId else { return }
        applyModelDefaults(for: modelId)
    }
}
