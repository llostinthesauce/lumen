import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
// MARK: - Shared UI bits
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
        Button(action: { action?() }) {
            HStack(spacing: 12) {
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

private struct CuratedModel: Identifiable {
    var id: String { folderName }
    let modelId: String
    let folderName: String
    let displayName: String
    let blurb: String
}

// MARK: - Manage Models (iOS)
struct ManageModelsView: View {
    @ObservedObject var state: AppState
    @Binding var selectedModel: String
    var onRefresh: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var modelFolders: [String] = []
    @State private var isLoadingModel = false
    @State private var errorMessage: String? = nil
    @State private var showError = false
    @State private var showImporter = false
    @State private var isImporting = false
    @State private var showSuccess = false
    @State private var successMessage = ""
    @State private var showDeleteConfirm = false
    @State private var iosDownloadProgress: Double = 0
    @State private var iosDownloadStatus: String = ""
    @State private var iosDownloadingModelId: String?
    
    private let iosCuratedModels: [CuratedModel] = [
        CuratedModel(
            modelId: "mlx-community/OpenELM-1_1B-Instruct-8bit",
            folderName: "OpenELM-1_1B-Instruct-8bit",
            displayName: "OpenELM 1.1B Instruct (8-bit)",
            blurb: "Tiny and quick—great starter for chat on-device."
        ),
        CuratedModel(
            modelId: "mlx-community/granite-4.0-h-micro-4bit",
            folderName: "granite-4.0-h-micro-4bit",
            displayName: "Granite 4.0 Micro (4-bit)",
            blurb: "Compact Granite model tuned for helpfulness."
        ),
        CuratedModel(
            modelId: "mlx-community/SmolLM3-3B-4bit",
            folderName: "SmolLM3-3B-4bit",
            displayName: "SmolLM3 3B (4-bit)",
            blurb: "Small 3B model with solid chat quality."
        ),
        CuratedModel(
            modelId: "mlx-community/gemma-3n-E2B-it-lm-4bit",
            folderName: "gemma-3n-E2B-it-lm-4bit",
            displayName: "Gemma 3n E2B (4-bit)",
            blurb: "Google Gemma nano variant for speed."
        ),
        CuratedModel(
            modelId: "mlx-community-staging/Llama-3.2-3B-Instruct-mlx-4Bit",
            folderName: "Llama-3.2-3B-Instruct-mlx-4Bit",
            displayName: "Llama 3.2 3B Instruct (4-bit)",
            blurb: "Balanced 3B llama for general chat."
        ),
        CuratedModel(
            modelId: "lmstudio-community/Qwen3-VL-2B-Instruct-MLX-8bit",
            folderName: "Qwen3-VL-2B-Instruct-MLX-8bit",
            displayName: "Qwen3-VL 2B (8-bit, vision)",
            blurb: "Vision-capable; use with image inputs where supported."
        )
    ]
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    iosCuratedDownloadList
                        .padding(.vertical, 4)
                } header: {
                    Text("Download (iOS curated)")
                } footer: {
                    Text("Downloads save into the iOS models folder. macOS manages models separately.")
                        .font(.caption)
                }
                
                Section {
                    Button(action: { showImporter = true }) {
                        HStack {
                            Image(systemName: "square.and.arrow.down.fill")
                            Text("Import Model")
                            Spacer()
                            if isImporting { ProgressView().scaleEffect(0.8) }
                        }
                    }
                    .disabled(isImporting)
                    
                    if modelFolders.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary.opacity(0.4))
                            Text("No models found")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("Download from the curated list or import a folder to begin.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    } else {
                        Picker("Model", selection: $selectedModel) {
                            Text("None").tag("")
                            ForEach(modelFolders, id: \.self) { model in
                                HStack {
                                    Text(model).lineLimit(1)
                                    Spacer()
                                    ModelFormatBadge(format: state.getModelFormat(for: model))
                                }
                                .tag(model)
                            }
                        }
                        .pickerStyle(.menu)
                        
                        if let blurb = selectedModelBlurb {
                            Text(blurb)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)
                        }
                        
                        Button(action: { loadModel() }) {
                            HStack {
                                if isLoadingModel {
                                    ProgressView().scaleEffect(0.8)
                                } else {
                                    Image(systemName: state.isModelLoaded ? "arrow.clockwise" : "arrow.down.circle.fill")
                                }
                                Text(isLoadingModel ? "Loading…" : (state.isModelLoaded ? "Reload Model" : "Load Model"))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedModel.isEmpty || isLoadingModel || isImporting)
                        
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete selected model", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(selectedModel.isEmpty || isImporting || isLoadingModel || iosDownloadingModelId != nil)
                    }
                } header: {
                    Text("Models")
                }
            }
            .navigationTitle("Manage Models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                refreshModelList()
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.folder, .data, .item],
                allowsMultipleSelection: true
            ) { result in
                handleImportResult(result)
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                if let error = errorMessage { Text(error) }
            }
            .alert("Success", isPresented: $showSuccess) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(successMessage)
            }
            .alert("Delete Model?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteSelectedModel()
                }
            } message: {
                Text("Remove \(selectedModel) from on-device storage.")
            }
        }
    }
    
    private var selectedModelBlurb: String? {
        iosCuratedModels.first { $0.folderName == selectedModel }?.blurb
    }
    
    private var iosCuratedDownloadList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(iosCuratedModels) { model in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.displayName)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text(model.blurb)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if iosDownloadingModelId == model.id {
                            Text("\(Int(iosDownloadProgress * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    if iosDownloadingModelId == model.id {
                        ProgressView(value: iosDownloadProgress)
                            .progressViewStyle(.linear)
                        if !iosDownloadStatus.isEmpty {
                            Text(iosDownloadStatus)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button { startCuratedDownload(model) } label: {
                            Label("Download to device", systemImage: "arrow.down.circle.fill")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isImporting || isLoadingModel)
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }
    
    private func refreshModelList() {
        modelFolders = state.listModelFolders()
    }
    
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
                await state.unloadCurrentModel()
                let threadId = state.getOrCreateThread(for: selectedModel)
                await MainActor.run {
                    state.selectedThreadID = threadId
                }
                let config = state.getCurrentConfig(for: selectedModel)
                try await state.engine.loadModel(at: modelURL, config: config)
                await MainActor.run {
                    state.currentModelURL = modelURL
                    state.isModelLoaded = true
                    if let multiEngine = state.engine as? MultiEngine {
                        state.currentEngineName = multiEngine.currentEngineName()
                    } else {
                        state.currentEngineName = "MLX"
                    }
                    state.updateSelected { thread in
                        thread.modelId = selectedModel
                        thread.config = config
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to load model: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }
    
    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { return }
            isImporting = true
            Task {
                do {
                    try ModelStorage.shared.importItems(urls: urls)
                    await MainActor.run {
                        isImporting = false
                        refreshModelList()
                        selectedModel = selectedModel.isEmpty ? modelFolders.first ?? "" : selectedModel
                        onRefresh()
                        successMessage = "Imported \(urls.count) item\(urls.count == 1 ? "" : "s")."
                        showSuccess = true
                    }
                } catch {
                    await MainActor.run {
                        isImporting = false
                        errorMessage = "Import failed: \(error.localizedDescription)"
                        showError = true
                    }
                }
            }
        case .failure(let error):
            errorMessage = "Import failed: \(error.localizedDescription)"
            showError = true
        }
    }
    
    private func startCuratedDownload(_ model: CuratedModel) {
        guard !isImporting else { return }
        isImporting = true
        iosDownloadingModelId = model.id
        iosDownloadProgress = 0
        iosDownloadStatus = "Starting…"
        
        Task.detached {
            do {
                try await HuggingFaceDownloader.downloadRepository(
                    modelId: model.modelId,
                    targetFolderName: model.folderName
                ) { progress, status in
                    Task { @MainActor in
                        iosDownloadProgress = progress
                        iosDownloadStatus = status
                    }
                }
                await MainActor.run {
                    iosDownloadStatus = "Download complete"
                    refreshModelList()
                    selectedModel = model.folderName
                    onRefresh()
                    successMessage = "Downloaded \(model.displayName)"
                    showSuccess = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Download failed: \(error.localizedDescription)"
                    showError = true
                }
            }
            await MainActor.run {
                isImporting = false
                iosDownloadingModelId = nil
            }
        }
    }
    
    private func deleteSelectedModel() {
        guard !selectedModel.isEmpty else { return }
        isImporting = true
        Task.detached {
            let currentSelection = await MainActor.run { state.currentModelURL }
            if let current = currentSelection, current.lastPathComponent == selectedModel {
                await state.unloadCurrentModel()
            }
            do {
                let modelName = await MainActor.run { selectedModel }
                try ModelStorage.shared.deleteModel(named: modelName)
                await MainActor.run {
                    refreshModelList()
                    selectedModel = modelFolders.first ?? ""
                    onRefresh()
                    successMessage = "Deleted model"
                    showSuccess = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Delete failed: \(error.localizedDescription)"
                    showError = true
                }
            }
            await MainActor.run {
                isImporting = false
            }
        }
    }
}

// MARK: - Personalization (iOS)
struct PersonalizationView: View {
    @ObservedObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    
    @State private var temperature: Double = 0.7
    @State private var maxTokens: Int = 256
    @State private var topP: Double = 0.95
    @State private var maxKV: Int = 256
    @State private var systemPrompt: String = "You are a helpful, concise assistant."
    @State private var trustRemoteCode: Bool = false
    
    var body: some View {
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
                                Stepper(value: $maxTokens, in: 1...4096, step: 32) { EmptyView() }
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
            .onAppear { loadConfig() }
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

// MARK: - Settings (iOS)
struct SettingsView: View {
    @ObservedObject var state: AppState
    var onRefresh: () -> Void
    @Binding var selectedModel: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    
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

    var body: some View {
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
                if let error = errorMessage { Text(error) }
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
                            ProgressView().scaleEffect(0.8)
                        }
                    }
                )
                .disabled(selectedModel.isEmpty || isLoadingModel || isImporting)
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
    
    private var isImporting: Bool {
        // ManageModelsView owns importing state; this flag prevents the load button when sheet open.
        // Here we just gate UI updates for safety.
        false
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
                await state.unloadCurrentModel()
                let threadId = state.getOrCreateThread(for: selectedModel)
                await MainActor.run {
                    state.selectedThreadID = threadId
                }
                let config = state.getCurrentConfig(for: selectedModel)
                try await state.engine.loadModel(at: modelURL, config: config)
                await MainActor.run {
                    state.currentModelURL = modelURL
                    state.isModelLoaded = true
                    if let multiEngine = state.engine as? MultiEngine {
                        state.currentEngineName = multiEngine.currentEngineName()
                    } else {
                        state.currentEngineName = "MLX"
                    }
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
