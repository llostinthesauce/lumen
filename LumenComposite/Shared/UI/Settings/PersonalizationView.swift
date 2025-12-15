import SwiftUI

public struct PersonalizationView: View {
    @ObservedObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    
    @State private var temperature: Double = 0.7
    @State private var maxTokens: Int = 256
    @State private var topP: Double = 0.95
    @State private var maxKV: Int = 256
    @State private var systemPrompt: String = "You are a helpful, concise assistant."
    @State private var trustRemoteCode: Bool = false
    
    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Temperature", systemImage: "thermometer")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            HStack(spacing: 12) {
                                Slider(value: $temperature, in: 0.0...2.0, step: 0.1)
                                .tint(.green)
                                Text(String(format: "%.2f", temperature))
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .frame(width: 50, alignment: .trailing)
                            }
                        }
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Max Tokens", systemImage: "number")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            HStack(spacing: 12) {
                                Stepper(value: $maxTokens, in: 1...4096, step: 32) {
                                    EmptyView()
                                }
                                Spacer()
                                Text("\(maxTokens)")
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .frame(width: 80, alignment: .trailing)
                            }
                        }
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Top P", systemImage: "chart.bar.fill")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            HStack(spacing: 12) {
                                Slider(value: $topP, in: 0.0...1.0, step: 0.05)
                                .tint(.blue)
                                Text(String(format: "%.2f", topP))
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .frame(width: 50, alignment: .trailing)
                            }
                        }
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Label("System Prompt", systemImage: "text.bubble")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            TextEditor(text: $systemPrompt)
                                .font(.caption)
                                .frame(minHeight: 80)
                        }
                    }
                } header: {
                    Text("Inference Settings")
                }
            }
            .navigationTitle("Personalization")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        saveConfig()
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadConfig()
            }
        }
    }
    
    private func loadConfig() {
        let config: InferenceConfig
        if state.manualOverrideEnabled {
            config = state.manualOverrideConfig
        } else if let threadConfig = state.selectedThread?.config {
            config = threadConfig
        } else {
            config = InferenceConfig()
        }
        
        temperature = config.temperature
        maxTokens = config.maxTokens
        topP = config.topP
        maxKV = config.maxKV
        systemPrompt = config.systemPrompt
        trustRemoteCode = config.trustRemoteCode
    }
    
    private func saveConfig() {
        let config = InferenceConfig(
            maxKV: maxKV,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            systemPrompt: systemPrompt,
            trustRemoteCode: trustRemoteCode
        )
        if state.manualOverrideEnabled {
            state.manualOverrideConfig = config
        }
        state.updateSelected { thread in
            thread.config = config
        }
        if state.isModelLoaded {
            state.engine.updateConfig(config)
        }
    }
}
