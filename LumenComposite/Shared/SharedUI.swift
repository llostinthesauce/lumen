import SwiftUI
import UniformTypeIdentifiers
import Combine
#if os(macOS)
import AppKit
#else
import UIKit
#endif

private let defaultEngine: ChatEngine = MultiEngine()

private func knowledgeBaseDocumentTypes() -> [UTType] {
    var types: [UTType] = [
        .plainText,
        .utf8PlainText,
        .utf16PlainText,
        .text,
        .content,
        .rtf,
        .rtfd,
        .pdf
    ]
    
    if let markdownType = UTType(filenameExtension: "md") {
        types.append(markdownType)
    }
    
    if let doc = UTType(filenameExtension: "doc") {
        types.append(doc)
    }
    if let docx = UTType(filenameExtension: "docx") {
        types.append(docx)
    }
    if let html = UTType(filenameExtension: "html") {
        types.append(html)
    }
    return types
}

public struct RootView: View {
    @ObservedObject var state: AppState
    @ObservedObject var sessionController: ChatSessionController
    @Environment(\.openURL) private var openURL
    
    @State private var modelFolders: [String] = []
    @State private var selectedModel: String = ""
    @State private var isImportingModels = false

    @State private var input: String = ""
    @State private var showSettings = false
    @State private var showImporter = false
    @State private var showExportSheet = false
    @State private var searchText = ""
    @State private var isSidebarVisible = true
#if os(iOS)
    @State private var threadToRename: ChatThread?
    @State private var renameTitle: String = ""
    @State private var showRenameSheet = false
    @State private var threadToDelete: ChatThread?
    @State private var showDeleteAlert = false
#endif
    @State private var showModelSwitchAlert = false
    @State private var pendingModelToSwitch: String?
    @AppStorage("useColorfulGradient") private var useColorfulGradient = false  // Default to off for better UI blending

    public init(state: AppState, sessionController: ChatSessionController) {
        self.state = state
        self.sessionController = sessionController
    }
    
    // MARK: - Shared Gradient
    /// Unified gradient background for both iOS and macOS - Apple native style
    /// More intense green-to-blue gradient with vibrant colors
    private var appGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.65, green: 0.95, blue: 0.75),  // Vibrant green
                Color(red: 0.55, green: 0.90, blue: 0.80),  // Green-cyan
                Color(red: 0.45, green: 0.85, blue: 0.88),  // Cyan-blue
                Color(red: 0.35, green: 0.75, blue: 0.95)   // Vibrant blue
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // Background that adapts based on gradient preference
    @ViewBuilder
    private var appBackground: some View {
        #if os(iOS)
        Color(.systemBackground)
        #else
        if useColorfulGradient {
            appGradient
        } else {
            Color(.windowBackgroundColor)
        }
        #endif
    }

#if os(iOS)
    public var body: some View {
        iosBody
    }
#else
    public var body: some View {
        macBody
    }
#endif
    
#if os(macOS)
    private var macBody: some View {
        MacOSMainView(
            state: state,
            sessionController: sessionController,
            modelFolders: $modelFolders,
            selectedModel: $selectedModel,
            isSidebarVisible: $isSidebarVisible,
            onModelsDetected: { refreshModelFolders() },
            onSelectModel: { switchToModel($0) }
        )

        .alert("Error", isPresented: $sessionController.showError) {
            Button("OK", role: .cancel) { }
        } message: {
            if let error = sessionController.errorMessage {
                Text(error)
            }
        }
        .onAppear {
            refreshModelFolders()
            refreshTokenHint()
        }
        .onChange(of: modelFolders) { newFolders in
            guard !newFolders.isEmpty else {
                selectedModel = ""
                return
            }
            if !newFolders.contains(selectedModel) {
                selectedModel = newFolders.first ?? ""
            }
        }
        .onChange(of: selectedModel) { _ in
            refreshTokenHint()
        }
        .onChange(of: state.selectedThread?.id) { _ in
            if let modelId = state.selectedThread?.modelId, !modelId.isEmpty {
                selectedModel = modelId
            }
            refreshTokenHint()
        }
        .alert("Switch Model?", isPresented: $showModelSwitchAlert) {
            Button("Switch", role: .destructive) {
                if let model = pendingModelToSwitch {
                    Task {
                        await state.unloadCurrentModel()
                        await MainActor.run {
                            performModelSwitch(to: model)
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                pendingModelToSwitch = nil
            }
        } message: {
            if let model = pendingModelToSwitch {
                Text("Switching to '\(model)' will unload the current model.")
            }
        }
    }
    

    #endif
    
    private var statusColor: Color {
        if state.isKnowledgeIndexing {
            return .blue
        } else if sessionController.isLoadingModel || isImportingModels {
            return .yellow
        } else if state.isModelLoaded {
            return .green
        } else {
            return .gray
        }
    }
    
    private var statusText: String {
        if sessionController.isStreaming {
            return "Generating…"
        } else if state.isKnowledgeIndexing {
            return "Indexing…"
        } else if sessionController.isLoadingModel || isImportingModels {
            return "Loading…"
        } else if state.isModelLoaded {
            return "Ready"
        } else if selectedModel.isEmpty {
            return "No Model"
        } else {
            return "Offline"
        }
    }
    
    private var statusChip: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(statusText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.thinMaterial, in: Capsule(style: .continuous))
        .fixedSize()
    }
    
    #if os(iOS)
    private var iosBody: some View {
        iOSMainView(
            state: state,
            sessionController: sessionController,
            modelFolders: $modelFolders,
            selectedModel: $selectedModel
        )
    }
    #endif
    


    
    private var filteredMessages: [Message] {
        let messages = state.selectedThread?.messages ?? []
        if searchText.isEmpty {
            return messages
        }
        return messages.filter { message in
            message.text.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private var filteredConversations: [ChatThread] {
        if searchText.isEmpty {
            return state.threads
        }
        return state.threads.filter { thread in
            thread.title.localizedCaseInsensitiveContains(searchText) ||
            thread.messages.contains { $0.text.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    private var isStreamingInCurrentThread: Bool {
        guard sessionController.isStreaming,
              let activeId = sessionController.activeStreamingThreadID,
              let selectedId = state.selectedThread?.id else { return false }
        return activeId == selectedId
    }
    
    private func workspaceBinding(for workspace: CodeWorkspace) -> Binding<Bool> {
        Binding(
            get: { state.selectedThread?.workspaceIDs.contains(workspace.id) ?? false },
            set: { newValue in
                state.updateSelected { thread in
                    if newValue {
                        if !thread.workspaceIDs.contains(workspace.id) {
                            thread.workspaceIDs.append(workspace.id)
                        }
                    } else {
                        thread.workspaceIDs.removeAll { $0 == workspace.id }
                    }
                }
            }
        )
    }
    
    private func copyMessage(_ message: Message) {
        #if os(iOS)
        UIPasteboard.general.string = message.text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.text, forType: .string)
        #endif
    }
    
    private func editMessage(_ message: Message) {
        input = message.text
    }
    
    private func deleteMessage(_ message: Message) {
        state.updateSelected { thread in
            thread.messages.removeAll { $0.id == message.id }
        }
    }
    
    private func regenerateResponse() {
        guard let thread = state.selectedThread,
              let lastUserMessage = thread.messages.last(where: { $0.role == .user }),
              let lastAssistantIndex = thread.messages.lastIndex(where: { $0.role == .assistant }) else {
            return
        }
        
        // Remove the last assistant response
        state.updateSelected { thread in
            thread.messages.remove(at: lastAssistantIndex)
        }
        
        // Resend the last user message
        input = lastUserMessage.text
        send()
    }
    
    private func exportConversation() {
        #if os(iOS)
        showExportSheet = true
        #else
        guard let thread = state.selectedThread else { return }
        let exportText = exportConversationText()
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = "\(thread.title).txt"
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                try? exportText.write(to: url, atomically: true, encoding: .utf8)
            }
        }
        #endif
    }
    
    private func exportConversationText() -> String {
        guard let thread = state.selectedThread else { return "" }
        
        var exportText = "# \(thread.title)\n\n"
        exportText += "Model: \(thread.modelId)\n"
        exportText += "Created: \(thread.statistics.createdAt.formatted())\n"
        exportText += "Last Activity: \(thread.statistics.lastActivity.formatted())\n\n"
        exportText += "---\n\n"
        
        for message in thread.messages {
            let role = message.role == .user ? "User" : "Assistant"
            exportText += "**\(role)** (\(message.timestamp.formatted()))\n\n"
            exportText += "\(message.text)\n\n"
            exportText += "---\n\n"
        }
        
        return exportText
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
    
    #if os(iOS)
    private func deleteThreads(at offsets: IndexSet) {
        for index in offsets {
            state.deleteThread(state.threads[index].id)
        }
    }
    #endif
    
    #if os(iOS)
    private var sidebarSelection: Binding<UUID?> {
        Binding(
            get: { state.selectedThreadID },
            set: { newValue in
                state.selectedThreadID = newValue
            }
        )
    }
    #endif
    
    private var currentModelIdentifier: String {
        if let threadModel = state.selectedThread?.modelId, !threadModel.isEmpty {
            return threadModel
        }
        return selectedModel
    }
    
    private var activeThreadConfig: InferenceConfig? {
        state.selectedThread?.config
    }
    
    private var selectedModelDisplayName: String {
        let active = currentModelIdentifier
        return active.isEmpty ? "Select Model" : active
    }
    
    private var canExportCurrentThread: Bool {
        guard let thread = state.selectedThread else { return false }
        return !thread.messages.isEmpty
    }
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search messages...", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .cornerRadius(10)
        #if os(iOS)
        .padding(.horizontal)
        .padding(.vertical, 8)
        #endif
    }
    
    private var messagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    emptyStateView
                    workspacesList
                    messagesList
                    streamingMessageView
                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: sessionController.filteredStreamText) { _ in
                guard isStreamingInCurrentThread else { return }
                withAnimation {
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
            }
            .onChange(of: sessionController.isStreaming) { newValue in
                guard newValue, isStreamingInCurrentThread else { return }
                withAnimation {
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
            }
            .onChange(of: state.selectedThread?.messages.count ?? 0) { _ in
                guard let lastMessage = state.selectedThread?.messages.last else { return }
                withAnimation {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
            #if os(iOS)
            .scrollContentBackground(.hidden)
            #endif
        }
    }
    
    @ViewBuilder
    private var emptyStateView: some View {
        if (state.selectedThread?.messages.isEmpty ?? true) && !isStreamingInCurrentThread {
            VStack(spacing: 16) {
                Image(systemName: state.threads.isEmpty ? "bubble.left.and.bubble.right" : "sparkles")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary.opacity(0.6))
                Text(state.threads.isEmpty ? "No Conversations" : "Start a conversation")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(state.threads.isEmpty ? "Tap the + button to create a new conversation" : "Select a model and send a message to begin")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(40)
            .frame(maxWidth: .infinity)
        }
    }
    
    @ViewBuilder
    private var workspacesList: some View {
        #if os(macOS)
        ForEach(state.codeWorkspaces) { workspace in
            HStack {
                Toggle(workspace.name, isOn: workspaceBinding(for: workspace))
                Spacer()
                
                if state.isKnowledgeIndexing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button(action: { state.reindexWorkspace(workspace) }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help("Scan Now")
                }
                
                Button(action: { state.toggleWatch(for: workspace.id) }) {
                    Image(systemName: workspace.isWatching ? "eye.fill" : "eye.slash")
                        .foregroundStyle(workspace.isWatching ? .blue : .secondary)
                }
                .buttonStyle(.plain)
                .help(workspace.isWatching ? "Stop Watching" : "Auto-Index Changes")
            }
        }
        .toggleStyle(.switch)
        #else
        EmptyView()
        #endif
    }
    
    @ViewBuilder
    private var messagesList: some View {
        ForEach(filteredMessages) { message in
            MessageBubble(
                message: message,
                onCopy: { copyMessage($0) },
                onEdit: { editMessage($0) },
                onDelete: { deleteMessage($0) },
                onRegenerate: { regenerateResponse() }
            )
            .id(message.id)
        }
    }
    
    @ViewBuilder
    private var streamingMessageView: some View {
        if isStreamingInCurrentThread {
            let streamingText = sessionController.filteredStreamText.isEmpty ? sessionController.streamText : sessionController.filteredStreamText
            MessageBubble(
                message: Message(role: .assistant, text: streamingText),
                isStreaming: true,
                showGenerating: streamingText.isEmpty
            )
            .id("streaming")
        }
    }
    
    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { return }
            Task {
                await MainActor.run {
                    isImportingModels = true
                }
                do {
                    try ModelStorage.shared.importItems(urls: urls)
                await MainActor.run {
                    isImportingModels = false
                    refreshModelFolders()
                    if modelFolders.count == 1 && selectedModel.isEmpty {
                        selectedModel = modelFolders[0]
                    }
                }
                } catch {
                await MainActor.run {
                        isImportingModels = false
                        sessionController.errorMessage = error.localizedDescription
                        sessionController.showError = true
                }
            }
            }
        case .failure(let error):
            sessionController.errorMessage = "Import failed: \(error.localizedDescription)"
            sessionController.showError = true
        }
    }

    private func refreshModelFolders(selectFirst: Bool = true) {
        modelFolders = sanitizedModelList(state.listModelFolders())
        if selectFirst && selectedModel.isEmpty {
            selectedModel = modelFolders.first ?? ""
        }
    }

    private func refreshTokenHint() {
        let modelId = selectedModel.isEmpty ? state.selectedThread?.modelId : selectedModel
        sessionController.refreshTokenHint(for: modelId)
    }
    
    private func switchToModel(_ model: String) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        #if os(iOS)
        guard !trimmed.lowercased().contains("gemma") else { return }
        #endif
        
        // Check if a different model is currently loaded
        if state.isModelLoaded, let current = state.currentModelURL?.lastPathComponent, current != trimmed {
            pendingModelToSwitch = trimmed
            showModelSwitchAlert = true
            return
        }
        
        performModelSwitch(to: trimmed)
    }
    
    private func performModelSwitch(to modelId: String) {
        if state.selectedThread?.modelId == modelId {
            selectedModel = modelId
            refreshTokenHint()
        } else {
            selectedModel = modelId
            let threadId = state.getOrCreateThread(for: modelId)
            state.selectedThreadID = threadId
            refreshTokenHint()
        }
        
        // Auto-load
        Task {
            try? await state.loadModel(modelId)
        }
    }

    private func send() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        input = ""
        let modelId = selectedModel
        Task {
            await sessionController.send(text: trimmed, selectedModel: modelId, attachments: [])
        }
    }
    
    private func sanitizedModelList(_ folders: [String]) -> [String] {
        folders.filter { !shouldHideModel($0) }
    }
    
    private func shouldHideModel(_ modelId: String) -> Bool {
        if modelId == embeddingModelIdentifier {
            return true
        }
        if let entry = ModelDefaultsRegistry.shared.entry(for: modelId),
           entry.tags?.contains(where: { $0.lowercased() == "embedding" }) == true {
            return true
        }
        return false
    }
    
    private var embeddingModelIdentifier: String { "all-MiniLM-L6-v2-8bit" }
}

#if !os(iOS)
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

// Manage Models View
struct ManageModelsView: View {
    @ObservedObject var state: AppState
    @Binding var selectedModel: String
    var onRefresh: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var modelFolders: [String] = []
    @State private var isLoadingModel = false
    @State private var errorMessage: String? = nil
    @State private var showError = false
    @State private var customPath: String = ""
    @State private var showPathPicker = false
    @State private var showImporter = false
    @State private var isImporting = false
    @State private var showSuccess = false
    @State private var successMessage = ""
    @State private var showDeleteConfirm = false
    #if os(iOS)
    @State private var iosDownloadProgress: Double = 0
    @State private var iosDownloadStatus: String = ""
    @State private var iosDownloadingModelId: String?
    #endif
    
    #if os(iOS)
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
    #endif
    
    var body: some View {
        NavigationStack {
            List {
                // Model Location Section
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Models Location")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            #if os(macOS)
                            Button("Change…") {
                                showPathPicker = true
                            }
                            #endif
                        }
                        
                        Text(ModelStorage.shared.modelsURL.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .padding(.vertical, 4)
                        
                        #if os(macOS)
                        HStack {
                            TextField("Custom path", text: $customPath)
                                .textFieldStyle(.roundedBorder)
                            Button("Set") {
                                if customPath.isEmpty {
                                    ModelStorage.shared.setCustomModelPath(nil)
                                } else {
                                    ModelStorage.shared.setCustomModelPath(customPath)
                                }
                                onRefresh()
                                modelFolders = state.listModelFolders()
                            }
                            Button("Reset") {
                                ModelStorage.shared.setCustomModelPath(nil)
                                customPath = ""
                                onRefresh()
                                modelFolders = state.listModelFolders()
                            }
                        }
                        #endif
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Storage")
                }
                
#if os(iOS)
                // Curated downloads for iOS (fixed list)
                Section {
                    iosCuratedDownloadList
                        .padding(.vertical, 4)
                } header: {
                    Text("Download (iOS curated)")
                } footer: {
                    Text("These downloads save into the iOS models folder. macOS manages models separately.")
                        .font(.caption)
                }
#endif
                
                // Models Section
                Section {
                    Button(action: {
                        showImporter = true
                    }) {
                        HStack {
                            Image(systemName: "square.and.arrow.down.fill")
                            Text("Import Model")
                            Spacer()
                            if isImporting {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .disabled(isImporting)
                    
                    if modelFolders.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary.opacity(0.4))
                            Text("No models found")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("Click 'Import Model' to add a model, or place model folders directly in the models directory.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        Picker("Model", selection: $selectedModel) {
                            Text("None").tag("")
                            ForEach(modelFolders, id: \.self) { model in
                                HStack {
                                    Text(model)
                                        .lineLimit(1)
                                    Spacer()
                                    ModelFormatBadge(format: state.getModelFormat(for: model))
                                }
                                .tag(model)
                            }
                        }
                        .pickerStyle(.menu)
#if os(iOS)
                        if let blurb = selectedModelBlurb {
                            Text(blurb)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 2)
                        }
#endif
                        
                        Button(action: { loadModel() }) {
                            HStack {
                                if isLoadingModel {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: state.isModelLoaded ? "arrow.clockwise" : "arrow.down.circle.fill")
                                }
                                Text(isLoadingModel ? "Loading…" : (state.isModelLoaded ? "Reload Model" : "Load Model"))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedModel.isEmpty || isLoadingModel || isImporting)
#if os(iOS)
                        
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete selected model", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(selectedModel.isEmpty || isImporting || isLoadingModel || iosDownloadingModelId != nil)
#endif
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
                customPath = ModelStorage.shared.customModelPath ?? ""
                refreshModelList()
            }
            #if os(macOS)
            .fileImporter(
                isPresented: $showPathPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        ModelStorage.shared.setCustomModelPath(url.path)
                        customPath = url.path
                        onRefresh()
                        modelFolders = state.listModelFolders()
                    }
                case .failure:
                    break
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.folder, .data, .item],
                allowsMultipleSelection: true
            ) { result in
                handleImportResult(result)
            }
            #else
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.folder, .data, .item],
                allowsMultipleSelection: true
            ) { result in
                handleImportResult(result)
            }
            #endif
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
            .alert("Success", isPresented: $showSuccess) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(successMessage)
            }
#if os(iOS)
            .alert("Delete Model?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteSelectedModel()
                }
            } message: {
                Text("Remove \(selectedModel) from on-device storage.")
            }
#endif
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
                    let config = state.selectedThread?.config ?? InferenceConfig()
                    try await state.engine.loadModel(at: modelURL, config: config)
                    await MainActor.run {
                        state.currentModelURL = modelURL
                        state.isModelLoaded = true
                        if let multiEngine = state.engine as? MultiEngine {
                            state.currentEngineName = multiEngine.currentEngineName()
                        } else {
                            state.currentEngineName = "MLX"
                        }
                    }
                    onRefresh()
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
    
#if os(iOS)
    private var selectedModelBlurb: String? {
        iosCuratedModels.first(where: { $0.folderName == selectedModel })?.blurb
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
                        Button {
                            startCuratedDownload(model)
                        } label: {
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
#endif
}

#if os(iOS)
private struct CuratedModel: Identifiable {
    var id: String { folderName }
    let modelId: String
    let folderName: String
    let displayName: String
    let blurb: String
}
#endif

// Personalization View
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
#endif

struct SettingsView: View {
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

    var body: some View {
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
#endif // !os(iOS)

#if os(macOS)
extension RootView {
    private func rebuildKnowledgeBase(includeCode: Bool = false) {
        startKnowledgeBaseRebuild(includeCode: includeCode)
    }
    
    private func startKnowledgeBaseRebuild(includeCode: Bool = false) {
        guard state.embeddingClient != nil else { return }
        Task {
            await state.rebuildKnowledgeBase(includeCode: includeCode)
        }
    }
    
    @ToolbarContentBuilder
    private var macToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(action: { isSidebarVisible.toggle() }) {
                Image(systemName: isSidebarVisible ? "sidebar.leading" : "sidebar.left")
            }
            .keyboardShortcut("\\", modifiers: .command)
            .help(isSidebarVisible ? "Hide Sidebar" : "Show Sidebar")
            
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .symbolRenderingMode(.multicolor)
                Text("Lumen")
                    .font(.system(size: 14, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                LinearGradient(
                    colors: [Color.blue.opacity(0.18), Color.green.opacity(0.18)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(18)
            
            statusChip
        }
        

    }
    

}
#endif

#if os(iOS)
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

struct MessageBubble: View {
    let message: Message
    var isStreaming: Bool = false
    var showGenerating: Bool = false
    var onCopy: ((Message) -> Void)? = nil
    var onEdit: ((Message) -> Void)? = nil
    var onDelete: ((Message) -> Void)? = nil
    var onRegenerate: (() -> Void)? = nil
    
    @State private var showActions = false
    #if os(macOS)
    @State private var isHovered = false
    #endif
    #if os(iOS)
    @Environment(\.colorScheme) private var colorScheme
    #endif
    
    private var actionButtonBackgroundColor: Color {
        #if os(macOS)
        return Color(NSColor.controlBackgroundColor).opacity(0.8)
        #else
        return Color(.systemBackground).opacity(0.8)
        #endif
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user {
                Spacer(minLength: 50)
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 8) {
                    #if os(macOS)
                    if message.role == .assistant {
                        actionButtons
                    }
                    #endif
                    
                    VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                        if showGenerating {
                            HStack(spacing: 8) {
                                GeneratingIndicator()
                                Text("Generating...")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                        } else if !message.text.isEmpty {
                            Text(message.text)
                                .textSelection(.enabled)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
#if os(iOS)
                                .background(message.role == .user ? userBubbleColor : assistantBubbleColor)
#else
                                .background(
                                    message.role == .user 
                                        ? Color(red: 0.0, green: 0.5, blue: 0.9)
                                        : Color.white.opacity(0.85)
                                )
#endif
                                .foregroundStyle(
                                    message.role == .user 
                                        ? .white 
                                        : .primary
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                        }
                    }
                    #if os(macOS)
                    if message.role == .user {
                        actionButtons
                    }
                    #endif
                }
                if message.role == .assistant,
                   let sources = message.referencedDocuments,
                   !sources.isEmpty {
                    DocumentSourcesView(sources: sources)
                        .frame(maxWidth: 420, alignment: .leading)
                }
                if isStreaming && !showGenerating && !message.text.isEmpty {
                    HStack(spacing: 4) {
                        TypingDot(delay: 0)
                        TypingDot(delay: 0.2)
                        TypingDot(delay: 0.4)
                    }
                    .padding(.leading, 12)
                    .padding(.top, 4)
                }
            }
            if message.role == .assistant {
                Spacer(minLength: 50)
            }
        }
        #if os(macOS)
        .onHover { hovering in
            isHovered = hovering
        }
        #endif
    }
    
    #if os(macOS)
    @ViewBuilder
    private var actionButtons: some View {
        if isHovered || showActions {
            HStack(spacing: 4) {
                if let onCopy = onCopy {
                    Button(action: { onCopy(message) }) {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                if message.role == .user, let onEdit = onEdit {
                    Button(action: { onEdit(message) }) {
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                if message.role == .assistant, let onRegenerate = onRegenerate, !isStreaming {
                    Button(action: { onRegenerate() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                if let onDelete = onDelete {
                    Button(action: { onDelete(message) }) {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(actionButtonBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
    #endif
    
    #if os(iOS)
    private var userBubbleColor: Color {
        if colorScheme == .dark {
            return Color.accentColor.opacity(0.6)
        } else {
            return Color.accentColor.opacity(0.85)
        }
    }
    
    private var assistantBubbleColor: Color {
        if colorScheme == .dark {
            return Color(UIColor.secondarySystemBackground).opacity(0.95)
        } else {
            return Color(UIColor.systemBackground).opacity(0.95)
        }
    }
    #endif
}

struct DocumentSourcesView: View {
    let sources: [String]
    
    private var formattedSources: String {
        sources.joined(separator: ", ")
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 1)
            Text(formattedSources)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.12))
        )
    }
}

struct GeneratingIndicator: View {
    @State private var rotation: Double = 0
    
    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: 16, height: 16)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

struct TypingDot: View {
    let delay: Double
    @State private var opacity: Double = 0.3
    
    var body: some View {
        Circle()
            .fill(Color.secondary)
            .frame(width: 6, height: 6)
            .opacity(opacity)
            .onAppear {
                withAnimation(
                    Animation.easeInOut(duration: 0.6)
                        .repeatForever()
                        .delay(delay)
                ) {
                    opacity = opacity == 0.3 ? 0.8 : 0.3
                }
            }
    }
}

struct ModelFormatBadge: View {
    let format: ModelFormat
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: formatIcon)
                .font(.caption2)
            Text(ModelFormatDetector.formatName(format))
                .font(.caption2)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(formatBackgroundColor)
        .foregroundStyle(formatForegroundColor)
        .cornerRadius(6)
    }
    
    private var formatIcon: String {
        switch format {
        case .mlx:
            return "bolt.fill"
        case .unknown:
            return "questionmark.circle"
        }
    }
    
    private var formatBackgroundColor: Color {
        switch format {
        case .mlx:
            return Color.blue.opacity(0.15)
        case .unknown:
            return Color.gray.opacity(0.15)
        }
    }
    
    private var formatForegroundColor: Color {
        switch format {
        case .mlx:
            return .blue
        case .unknown:
            return .gray
        }
    }
}



#if os(iOS)
private struct RenameConversationSheet: View {
    let title: String
    @Binding var newTitle: String
    var onCancel: () -> Void
    var onSave: (String) -> Void
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Conversation title", text: $newTitle)
                        .textFieldStyle(.roundedBorder)
                }
                Section {
                    Text("Give your chat a memorable name so you can find it later. Names stay local to your device.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Rename Conversation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(newTitle.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// Legacy ThreadRow - kept for compatibility but not used in new design
struct ThreadRow: View {
    let thread: ChatThread
    @ObservedObject var state: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(thread.title)
                .lineLimit(1)
                .font(.body)
            if !thread.modelId.isEmpty {
                Text(thread.modelId)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func listSectionSpacingCompat(_ value: CGFloat) -> some View {
        if #available(iOS 17.0, *) {
            self.listSectionSpacing(value)
        } else {
            self
        }
    }
}
#endif

#if os(macOS)
// Editable thread row for macOS sidebar
struct EditableThreadRow: View {
    let thread: ChatThread
    @ObservedObject var state: AppState
    @State private var isEditing = false
    @State private var editedTitle: String = ""
    
    var body: some View {
        HStack {
            if isEditing {
                TextField("Thread name", text: $editedTitle)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        commitEdit()
                    }
                    .onExitCommand {
                        cancelEdit()
                    }
            } else {
                Text(thread.title)
                    .lineLimit(1)
                Spacer()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            startEditing()
        }
        .onChange(of: thread.id) { _ in
            if thread.id == state.selectedThreadID {
                editedTitle = thread.title
            }
        }
    }
    
    private func startEditing() {
        editedTitle = thread.title
        isEditing = true
    }
    
    private func commitEdit() {
        if !editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            state.updateThreadTitle(thread.id, to: editedTitle.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        isEditing = false
    }
    
    private func cancelEdit() {
        isEditing = false
        editedTitle = thread.title
    }
}
#endif

// MARK: - iOS Components

struct IOSTopBarPillView: View {
    let modelName: String
    let statusText: String
    let statusColor: Color
    let onTapSettings: () -> Void
    
    var body: some View {
        HStack {
            // Model Name
            Text(modelName.isEmpty ? "Lumen" : modelName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
            
            Spacer()
            
            // Status Indicator
            if !statusText.isEmpty {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text(statusText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
            }
            
            // Settings Button
            Button(action: onTapSettings) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
        .overlay(
            Capsule()
                .stroke(.white.opacity(0.2), lineWidth: 0.5)
        )
    }
}

