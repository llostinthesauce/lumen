import SwiftUI

public struct SettingsView: View {
    @ObservedObject var state: AppState
    var onRefresh: () -> Void
    @Binding var selectedModel: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    
    @AppStorage("useModelColorIndicators") private var useModelColorIndicators = true
    @State private var modelFolders: [String] = []
    @State private var isLoadingModel = false
    @State private var errorMessage: String? = nil
    @State private var showError = false
    
    @State private var showDeleteAlert = false
    @State private var showManageModels = false
    @State private var showPersonalization = false
    @State private var showTerms = false
    @State private var showPrivacy = false
    @State private var showLicenses = false

    public init(state: AppState, selectedModel: Binding<String>, onRefresh: @escaping () -> Void) {
        self.state = state
        self._selectedModel = selectedModel
        self.onRefresh = onRefresh
    }

    public var body: some View {
        #if os(iOS)
        iosSettingsContent
        #else
        Text("Settings are available in the iOS build.")
            .padding()
        #endif
    }
    
    #if os(iOS)
    private var iosSettingsContent: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        settingsHeader
                        modelSection
                        generationSection
                        conversationSection
                        aboutSection
                    }
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
            }
            .sheet(isPresented: $showManageModels) {
                ManageModelsView(state: state, selectedModel: $selectedModel) {
                    refreshModelList()
                    onRefresh()
                }
            }
            .sheet(isPresented: $showPersonalization) {
                PersonalizationView(state: state)
            }
            .sheet(isPresented: $showTerms) {
                TermsAndConditionsView()
            }
            .sheet(isPresented: $showPrivacy) {
                PrivacyPolicyView()
            }
            .sheet(isPresented: $showLicenses) {
                LicensesView()
            }
            .onAppear {
                refreshModelList()
                seedSelectedModelIfNeeded()
            }
            .onChange(of: showManageModels) { presented in
                if !presented {
                    refreshModelList()
                }
            }
            .onChange(of: modelFolders) { folders in
                if selectedModel.isEmpty, let first = folders.first {
                    selectedModel = first
                }
            }
            .alert("Delete All Conversations", isPresented: $showDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    state.clearAllThreads()
                }
            } message: {
                Text("This removes your on-device conversation history. RAG and context are macOS-only, so only chats are affected on iOS.")
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
        }
    }
    
    private var settingsHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("On-device chat, tuned for iPhone and iPad")
                .font(.headline)
            Text("Pick which local model to run, adjust generation defaults, and manage history. Retrieval and coding context stay on macOS.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
    }
    
    private var modelSection: some View {
        SettingsSection(title: "On-Device Model") {
            VStack(spacing: 0) {
                modelOverviewCard
                SettingsDivider()
                SettingsRow(
                    icon: Image(systemName: "doc.text.fill"),
                    iconOverlay: Image(systemName: "gearshape.fill"),
                    title: "Manage models",
                    action: { showManageModels = true }
                )
                SettingsDivider()
                SettingsRow(
                    icon: Image(systemName: state.isModelLoaded ? "arrow.clockwise" : "arrow.down.circle.fill"),
                    title: state.isModelLoaded ? "Reload selected model" : "Load selected model",
                    action: { loadModel() },
                    trailing: {
                        if isLoadingModel {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                )
                .disabled(selectedModel.isEmpty || isLoadingModel)
            }
        }
    }
    
    private var modelOverviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedModel.isEmpty ? "No model selected" : selectedModel)
                        .font(.body)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Text(modelStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(selectedModelIsLoaded ? "Loaded" : "Ready")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background((selectedModelIsLoaded ? Color.green : Color.secondary).opacity(0.15))
                    .foregroundStyle(selectedModelIsLoaded ? Color.green : Color.secondary)
                    .clipShape(Capsule())
            }
            
            HStack(spacing: 8) {
                if !selectedModel.isEmpty {
                    ModelFormatBadge(format: state.getModelFormat(for: selectedModel))
                }
                capabilityBadges
                Spacer()
                Text(availableModelsText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }
    
    private var capabilityBadges: some View {
        let caps = selectedModelCapabilities
        return HStack(spacing: 6) {
            capabilityTag(state.currentEngineName.isEmpty ? "MLX" : state.currentEngineName, systemImage: "sparkles")
            if caps.contains(.visionInput) {
                capabilityTag("Vision ready", systemImage: "eye")
            }
        }
    }
    
    @ViewBuilder
    private func capabilityTag(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.caption2)
            Text(text)
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(.secondarySystemBackground))
        .clipShape(Capsule())
    }
    
    private var generationSection: some View {
        SettingsSection(title: "Generation Defaults") {
            SettingsRow(
                icon: Image(systemName: "switch.2"),
                title: "Manual override for all chats",
                showChevron: false,
                trailing: {
                    Toggle("", isOn: $state.manualOverrideEnabled)
                        .labelsHidden()
                }
            )
            SettingsDivider()
            SettingsRow(
                icon: Image(systemName: "slider.horizontal.3"),
                title: "Tuning & system prompt",
                action: { showPersonalization = true },
                trailing: {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(inferenceSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(systemPromptPreview)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            )
        }
    }
    
    private var conversationSection: some View {
        SettingsSection(title: "Conversation & Appearance") {
            SettingsRow(
                icon: Image(systemName: "archivebox.fill"),
                title: "Save chat history on device",
                showChevron: false,
                trailing: {
                    Toggle("", isOn: Binding(
                        get: { state.saveChatHistory },
                        set: { newValue in
                            state.saveChatHistory = newValue
                        }
                    ))
                    .labelsHidden()
                }
            )
            SettingsDivider()
            SettingsRow(
                icon: Image(systemName: "paintpalette.fill"),
                title: "Color-code model indicators",
                showChevron: false,
                trailing: {
                    Toggle("", isOn: $useModelColorIndicators)
                        .labelsHidden()
                }
            )
            SettingsDivider()
            SettingsRow(
                icon: Image(systemName: "trash.fill"),
                title: "Delete conversation history",
                isDestructive: true,
                action: { showDeleteAlert = true }
            )
        }
    }
    
    private var aboutSection: some View {
        SettingsSection(title: "About & Support") {
            SettingsRow(
                icon: Image(systemName: "doc.text.fill"),
                iconOverlay: Image(systemName: "checkmark.circle.fill"),
                title: "Terms & Conditions",
                action: { showTerms = true }
            )
            SettingsDivider()
            SettingsRow(
                icon: Image(systemName: "lock.fill"),
                title: "Privacy Policy",
                action: { showPrivacy = true }
            )
            SettingsDivider()
            SettingsRow(
                icon: Image(systemName: "doc.text.fill"),
                title: "Licenses",
                action: { showLicenses = true }
            )
            SettingsDivider()
            SettingsRow(
                icon: Image(systemName: "link"),
                title: "Source & releases",
                action: {
                    if let url = URL(string: "https://github.com/llostinthesauce/Lumen") {
                        openURL(url)
                    }
                }
            )
            SettingsDivider()
            SettingsRow(
                icon: Image(systemName: "info.circle.fill"),
                title: "Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")",
                showChevron: false
            )
        }
    }
    
    private var inferenceSummary: String {
        let config = currentConfig
        let temperatureText = String(format: "%.1f", config.temperature)
        let topPText = String(format: "%.2f", config.topP)
        return "Temp \(temperatureText) • Top P \(topPText) • Max \(config.maxTokens)"
    }
    
    private var systemPromptPreview: String {
        let prompt = currentConfig.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if prompt.isEmpty {
            return "Using default assistant prompt"
        }
        return prompt
    }
    
    private var selectedModelCapabilities: ModelCapabilities {
        let url = state.findModelURL(for: selectedModel)
        return ModelCapabilityDetector.capabilities(for: selectedModel, modelURL: url)
    }
    
    private var selectedModelIsLoaded: Bool {
        guard let current = state.currentModelURL else { return false }
        return state.isModelLoaded && current.lastPathComponent == selectedModel
    }
    
    private var modelStatusText: String {
        if selectedModel.isEmpty {
            return "Pick a model to start chatting."
        }
        if selectedModelIsLoaded {
            let engine = state.currentEngineName.isEmpty ? "MLX" : state.currentEngineName
            return "Loaded via \(engine)"
        }
        let formatName = ModelFormatDetector.formatName(state.getModelFormat(for: selectedModel))
        if formatName == "Unknown" {
            return "Install or import this model to load it."
        }
        return "Ready to load (\(formatName))"
    }
    
    private var availableModelsText: String {
        if modelFolders.isEmpty {
            return "No models installed"
        }
        return "\(modelFolders.count) installed"
    }
    
    private var currentConfig: InferenceConfig {
        if state.manualOverrideEnabled {
            return state.manualOverrideConfig
        }
        return state.selectedThread?.config ?? InferenceConfig()
    }
    
    private func refreshModelList() {
        modelFolders = state.listModelFolders()
    }
    
    private func seedSelectedModelIfNeeded() {
        if selectedModel.isEmpty {
            if let threadModel = state.selectedThread?.modelId, !threadModel.isEmpty {
                selectedModel = threadModel
            } else if let loaded = state.currentModelURL?.lastPathComponent {
                selectedModel = loaded
            } else if let first = modelFolders.first {
                selectedModel = first
            }
        }
    }
    #endif
    
    private func loadModel() {
        guard !selectedModel.isEmpty else { return }
        isLoadingModel = true
        let modelId = selectedModel
        
        Task {
            defer { isLoadingModel = false }
            do {
                guard let modelURL = state.findModelURL(for: modelId) else {
                    await MainActor.run {
                        errorMessage = "Model '\(selectedModel)' not found."
                        showError = true
                    }
                    return
                }
                let validation = ModelValidator.validate(at: modelURL)
                if !validation.isValid {
                    await MainActor.run {
                        errorMessage = ModelValidator.errorMessage(from: validation)
                        showError = true
                    }
                    return
                }
                if !validation.warnings.isEmpty {
                    let warningText = validation.warnings.joined(separator: "\n• ")
                    print("Model warnings: \(warningText)")
                }
                // Ensure previous model is unloaded before loading the new one.
                await state.unloadCurrentModel()
                // Ensure a thread exists and is aligned to this model.
                let threadId = state.getOrCreateThread(for: selectedModel)
                await MainActor.run {
                    state.selectedThreadID = threadId
                }
                let config = state.getCurrentConfig(for: selectedModel)
                try await state.engine.loadModel(at: modelURL, config: config)
                await MainActor.run {
                    state.currentModelURL = modelURL
                    state.isModelLoaded = true
                    state.currentEngineName = "MLX" // Directly set as per refactoring plan
                    state.updateSelected { thread in
                        thread.modelId = selectedModel
                        thread.config = config
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = formatModelError(error)
                    showError = true
                }
            }
        }
    }
    
    private func formatModelError(_ error: Error) -> String {
        let errorDesc = error.localizedDescription
        let errorString = String(describing: error)
        
        if errorDesc.contains("safetensors") || errorString.contains("safetensors") ||
           errorDesc.contains("SafeTensors") || errorString.contains("SafeTensors") {
            return "Error loading model weights: \(errorDesc)\n\nThis usually means:\n• The model files are corrupted or incomplete\n• The safetensors format is incompatible\n• Try re-downloading the model or use a different model"
        } else if errorDesc.contains("memory") || errorDesc.contains("Memory") || 
                  errorDesc.contains("too large") || errorDesc.contains("allocation") {
            return "Model too large for device memory. Try a smaller model (under 1B parameters, 4-bit quantized). Recommended: Qwen1.5-0.5B-Chat-4bit or OpenELM-270M-Instruct"
        } else {
            return "Failed to load model: \(errorDesc)"
        }
    }
}

#if os(iOS)
struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
            
            VStack(spacing: 0) {
                content
            }
            .background(Color(.systemBackground))
            .cornerRadius(10)
            .padding(.horizontal, 20)
        }
    }
}

struct SettingsRow<Trailing: View>: View {
    let icon: Image
    var iconOverlay: Image? = nil
    let title: String
    var isDestructive: Bool = false
    var showChevron: Bool = true
    var action: (() -> Void)? = nil
    @ViewBuilder var trailing: () -> Trailing
    
    init(
        icon: Image,
        iconOverlay: Image? = nil,
        title: String,
        isDestructive: Bool = false,
        showChevron: Bool = true,
        action: (() -> Void)? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.icon = icon
        self.iconOverlay = iconOverlay
        self.title = title
        self.isDestructive = isDestructive
        self.showChevron = showChevron
        self.action = action
        self.trailing = trailing
    }
    
    var body: some View {
        Button(action: {
            action?()
        }) {
            HStack(spacing: 12) {
                // Icon with optional overlay
                ZStack {
                    icon
                        .font(.system(size: 20))
                        .foregroundStyle(isDestructive ? .red : .primary)
                    
                    if let overlay = iconOverlay {
                        overlay
                            .font(.system(size: 10))
                            .foregroundStyle(.primary)
                            .offset(x: 8, y: 8)
                    }
                }
                .frame(width: 28, height: 28)
                
                Text(title)
                    .font(.system(size: 17))
                    .foregroundStyle(isDestructive ? .red : .primary)
                
                Spacer()
                
                trailing()
                
                if showChevron && action != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 56)
    }
}

struct SettingsButton: View {
    let title: String
    let systemImage: String
    var isDisabled: Bool = false
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isDisabled)
    }
}
#endif
