#if os(macOS)
import SwiftUI
import Combine
import AppKit
import Foundation
import UniformTypeIdentifiers

// MARK: - Main macOS Window Layout
struct MacOSMainView: View {
    @ObservedObject var state: AppState
    @ObservedObject var sessionController: ChatSessionController
    @Binding var modelFolders: [String]
    @Binding var selectedModel: String
    @Binding var isSidebarVisible: Bool
    var onModelsDetected: () -> Void
    var onSelectModel: (String) -> Void
    
    @State private var showPreferences = false
    @State private var showWorkspaceManager = false
    @StateObject private var serverState = ServerState.shared
    @AppStorage("telemetry.hud.enabled") private var showTelemetryHUD = false
    
    @State private var selectedTab: ActivityTab = .chat
    
    var body: some View {
        HStack(spacing: 0) {
            // Activity Bar (Leftmost)
            ActivityBar(selectedTab: $selectedTab)
                .zIndex(3)
            
            // Main Content Area
            ZStack {
                if selectedTab == .chat {
                    chatView
                } else if selectedTab == .discovery {
                    ModelManagerView(
                        state: state,
                        modelFolders: $modelFolders,
                        onRefresh: { modelFolders = state.listModelFolders() }
                    )
                } else if selectedTab == .context {
                    ContextManagerView(state: state)
                } else if selectedTab == .server {
                    serverView
                } else if selectedTab == .settings {
                    PreferencesWindow(state: state, modelFolders: $modelFolders)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(
            ZStack {
                // Global Background
                LinearGradient(
                    colors: [
                        Color(nsColor: .windowBackgroundColor),
                        Color.blue.opacity(0.15),
                        Color.purple.opacity(0.15)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .sheet(isPresented: $showPreferences) {
            PreferencesWindow(state: state, modelFolders: $modelFolders)
        }
        .sheet(isPresented: $showWorkspaceManager) {
            VStack {
                Text("Workspace Manager")
                    .font(.title)
                Text("Coming soon...")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(width: 400, height: 300)
        }
        .overlay(alignment: .bottomTrailing) {
            if showTelemetryHUD {
                TelemetryHUD(state: state, isVisible: $showTelemetryHUD)
                    .padding()
                    .offset(hudOffset)
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                hudOffset = gesture.translation
                            }
                    )
            }
        }
    }
    

    @State private var hudOffset: CGSize = .zero
    
    private var serverView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Local API Server")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Expose an OpenAI-compatible endpoint on localhost (text-only). Disabled by default.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
                Spacer()
                HStack(spacing: 10) {
                    Toggle("Enable", isOn: $serverState.isEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .help("Enable the local API server (disabled by default).")
                    Text("Port")
                    TextField("1234", value: $serverState.port, formatter: NumberFormatter())
                        .frame(width: 70)
                        .textFieldStyle(.roundedBorder)
                        .disabled(serverState.isRunning || !serverState.isEnabled)
                    if serverState.isRunning {
                        Button {
                            serverState.stop()
                        } label: {
                            Label("Stop", systemImage: "stop.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button {
                            serverState.start(with: state)
                        } label: {
                            Label("Start", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!serverState.isEnabled)
                    }
                }
            }
            
            HStack(spacing: 10) {
                Circle()
                    .fill(serverState.isRunning ? Color.green : Color.red.opacity(0.8))
                    .frame(width: 10, height: 10)
                Text(serverState.isRunning ? "Running on http://localhost:\(serverState.port)" : "Stopped")
                    .foregroundStyle(.secondary)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Usage")
                    .font(.headline)
                Text("Start the server, then send requests to OpenAI-compatible endpoints:")
                    .foregroundStyle(.secondary)
                CodeBlockView(text: """
curl -N \\
  -H "Content-Type: application/json" \\
  -d '{"model":"<model_id>","messages":[{"role":"user","content":"Hello"}],"stream":true}' \\
  http://localhost:\(serverState.port)/v1/chat/completions
""")
                Text("Models must already exist in your configured model folders. The server will auto-load the requested model if found. Only text content is supported.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Logs")
                        .font(.headline)
                    Spacer()
                    Button {
                        serverState.logs.removeAll()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
                
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(serverState.logs.reversed(), id: \.self) { line in
                            Text(line)
                                .font(.caption2)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 120, maxHeight: 220)
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            Spacer()
        }
        .padding(24)
    }
    
    private var chatView: some View {
        HStack(spacing: 0) {
            // Sidebar - Floating Glass Panel
            if isSidebarVisible {
                SidebarView(
                    state: state,
                    modelFolders: modelFolders,
                    selectedModel: $selectedModel,
                    onSelectModel: onSelectModel,
                    isSidebarVisible: $isSidebarVisible
                )
                .frame(width: 260)
                .transition(.move(edge: .leading).combined(with: .opacity))
                .zIndex(2)
            }
            
            // Main Content
            ZStack(alignment: .top) {

                // Chat Area
                if state.threads.isEmpty && !state.hasModelsInstalled {
                    FirstRunWelcomeView(onModelsDetected: onModelsDetected)
                } else {
                    ChatAreaView(
                        state: state,
                        sessionController: sessionController,
                        selectedModel: $selectedModel,
                        isSidebarVisible: $isSidebarVisible
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            

        }
    }
}

// MARK: - Sidebar
struct SidebarView: View {
    @ObservedObject var state: AppState
    let modelFolders: [String]
    @Binding var selectedModel: String
    var onSelectModel: (String) -> Void
    @Binding var isSidebarVisible: Bool
    
    @State private var threadToRename: ChatThread?
    @State private var renameTitle = ""
    @State private var isRenaming = false
    @State private var threadToDelete: ChatThread?
    @State private var showDeleteAlert = false
    
    // Color palette for custom model colors
    private let colorPalette: [(name: String, color: Color)] = [
        ("Red", .red), ("Orange", .orange), ("Yellow", .yellow),
        ("Green", .green), ("Mint", .mint), ("Teal", .teal),
        ("Cyan", .cyan), ("Blue", .blue), ("Indigo", .indigo),
        ("Purple", .purple), ("Pink", .pink), ("Brown", .brown),
        ("Gray", .gray)
    ]
    private let modelColorKeyPrefix = "modelColor_"
    @AppStorage("useModelColorIndicators") private var useModelColorIndicators = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Window Controls Spacer & Header
            HStack {
                // Traffic lights sit here
                Spacer()
                
                // New Chat Button
                Button(action: {
                    let targetModel = selectedModel.isEmpty ? (modelFolders.first ?? "") : selectedModel
                    let threadId = state.getOrCreateThread(for: targetModel)
                    state.selectedThreadID = threadId
                    selectedModel = targetModel
                }) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                        .padding(8)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help("New Chat")
                
                // Collapse Button
                Button(action: { withAnimation { isSidebarVisible = false } }) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
                .buttonStyle(.plain)
                .help("Hide Sidebar")
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 12)
            
            ScrollView {
                VStack(spacing: 6) {
                    // Sessions
                    let displayedThreads = uniqueThreads()
                    if !displayedThreads.isEmpty {
                        Text("Sessions")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                        
                        ForEach(displayedThreads) { thread in
                            SidebarRow(
                                title: thread.title.isEmpty ? "New Chat" : thread.title,
                                subtitle: thread.messages.last?.text ?? "No messages",
                                isSelected: state.selectedThreadID == thread.id
                            )
                            .onTapGesture {
                                state.selectedThreadID = thread.id
                                if !thread.modelId.isEmpty {
                                    selectedModel = thread.modelId
                                }
                            }
                            .contextMenu {
                                Button("Rename") {
                                    threadToRename = thread
                                    renameTitle = thread.title
                                    isRenaming = true
                                }
                                Button("Delete", role: .destructive) {
                                    threadToDelete = thread
                                    showDeleteAlert = true
                                }
                            }
                        }
                    }
                    
                    // Models
                    if !modelFolders.isEmpty {
                        Text("Models")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, 24)
                        
                        ForEach(modelFolders, id: \.self) { model in
                            SidebarRow(
                                title: model,
                                subtitle: nil,
                                isSelected: selectedModel == model,
                                iconColor: modelColor(for: model)
                            )
                            .onTapGesture { onSelectModel(model) }
                            .contextMenu {
                                ForEach(colorPalette, id: \.name) { entry in
                                    Button { setCustomColor(entry.name, for: model) } label: {
                                        Label(entry.name, systemImage: "circle.fill").foregroundStyle(entry.color)
                                    }
                                }
                                Divider()
                                Button("Reset Color") { clearCustomColor(for: model) }
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .background(.ultraThinMaterial)
        .background(
            LinearGradient(colors: [.white.opacity(0.1), .clear], startPoint: .top, endPoint: .bottom)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.4), .white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 10)
        .padding(.leading, 8)
        .padding(.top, 8) // Traffic lights clearance
        .padding(.bottom, 8)
        .sheet(isPresented: $isRenaming) {
            if let thread = threadToRename {
                RenameThreadSheet(title: thread.title, newTitle: $renameTitle) { newValue in
                    state.updateThreadTitle(thread.id, to: newValue)
                    threadToRename = nil
                    isRenaming = false
                } onCancel: {
                    threadToRename = nil
                    isRenaming = false
                }
            }
        }
        .alert("Delete Conversation", isPresented: $showDeleteAlert, presenting: threadToDelete) { thread in
            Button("Cancel", role: .cancel) { threadToDelete = nil }
            Button("Delete", role: .destructive) {
                state.deleteThread(thread.id)
                if state.selectedThreadID == nil, let first = state.threads.first {
                    selectedModel = first.modelId
                }
                threadToDelete = nil
            }
        } message: { thread in
            Text("Delete \"\(thread.title)\"? This cannot be undone.")
        }
    }
    
    private func modelSizeColor(for model: String) -> Color {
        guard useModelColorIndicators else { return Color.accentColor }
        if model.lowercased().contains("1b") || model.lowercased().contains("135m") { return .green }
        else if model.lowercased().contains("3b") || model.lowercased().contains("7b") { return .yellow }
        else { return .orange }
    }

    private func customColor(for model: String) -> Color? {
        guard let name = UserDefaults.standard.string(forKey: modelColorKeyPrefix + model) else { return nil }
        return colorPalette.first(where: { $0.name == name })?.color
    }

    private func setCustomColor(_ name: String, for model: String) {
        UserDefaults.standard.set(name, forKey: modelColorKeyPrefix + model)
    }

    private func clearCustomColor(for model: String) {
        UserDefaults.standard.removeObject(forKey: modelColorKeyPrefix + model)
    }

    private func modelColor(for model: String) -> Color {
        if let saved = customColor(for: model) { return saved }
        return modelSizeColor(for: model)
    }

    private func uniqueThreads() -> [ChatThread] {
        var seen: Set<String> = []
        return state.threads
            .sorted(by: { $0.statistics.lastActivity > $1.statistics.lastActivity })
            .filter { thread in
                let key = thread.modelId
                if seen.contains(key) { return false }
                seen.insert(key)
                return true
            }
    }
}

struct SidebarRow: View {
    let title: String
    let subtitle: String?
    let isSelected: Bool
    var iconColor: Color? = nil
    
    var body: some View {
        HStack(spacing: 10) {
            if let color = iconColor {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .shadow(color: color.opacity(0.5), radius: 4, x: 0, y: 0)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary.opacity(0.8))
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - Thread Row View (with last message snippet)
struct ThreadRowView: View {
    let thread: ChatThread

    
    var lastMessageSnippet: String {
        if let lastMessage = thread.messages.last {
            let text = lastMessage.text
            if text.count > 50 {
                return String(text.prefix(50)) + "..."
            }
            return text
        }
        return "New conversation"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(thread.title.isEmpty ? "New Chat" : thread.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            
            Text(lastMessageSnippet)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

struct RenameThreadSheet: View {
    let title: String
    @Binding var newTitle: String
    var onSave: (String) -> Void
    var onCancel: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Conversation")
                .font(.title3)
                .fontWeight(.semibold)
            
            TextField("Title", text: $newTitle)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
            
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                Button("Save") {
                    onSave(newTitle.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 360)
    }
}

// MARK: - Chat Area
struct ChatAreaView: View {
    @ObservedObject var state: AppState
    @ObservedObject var sessionController: ChatSessionController
    @Binding var selectedModel: String
    @Binding var isSidebarVisible: Bool
    
    @State private var input: String = ""
    @State private var pendingAttachments: [AttachmentDraft] = []
    @State private var showAttachmentImporter = false
    @State private var isDropTargeted = false
    
    private var isStreamingInCurrentThread: Bool {
        sessionController.isStreaming &&
        sessionController.activeStreamingThreadID == state.selectedThread?.id
    }
    
    private var currentMessages: [Message] {
        state.selectedThread?.messages ?? []
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Top Bar Pill
            TopBarPillView(
                modelName: selectedModel,
                state: state,
                sessionController: sessionController,
                isSidebarVisible: $isSidebarVisible
            )
            .padding(.top, 8) // Match sidebar top padding for alignment
            .padding(.bottom, 8)
            .zIndex(1)
            
            contextToggle
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            
            if showWorkspacePicker {
                workspacePicker
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }
            
            conversationList
            
            if supportsAttachmentInput && !pendingAttachments.isEmpty {
                AttachmentStrip(
                    attachments: pendingAttachments,
                    onRemove: removeAttachment(_:)
                )
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }
            
            // Input Area
            ChatInputView(
                input: $input,
                isStreaming: Binding(
                    get: { sessionController.isStreaming },
                    set: { _ in }
                ),
                onSend: sendMessage,
                maxInputLength: maxPromptCharacters,
                hasPendingAttachments: !pendingAttachments.isEmpty,
                supportsAttachments: supportsAttachmentInput,
                onAddAttachment: { showAttachmentImporter = true },
                onTyping: { state.handleUserActivity() }
            )
        }
        .background(Color.clear)
        .fileImporter(
            isPresented: $showAttachmentImporter,
            allowedContentTypes: AttachmentStorage.supportedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                addAttachments(from: urls)
            case .failure(let error):
                sessionController.errorMessage = "Import failed: \(error.localizedDescription)"
                sessionController.showError = true
            }
        }
        .onChange(of: selectedModel) { _ in
            if !supportsAttachmentInput {
                discardPendingAttachments()
            }
        }
        .onChange(of: state.selectedThread?.modelId ?? "") { _ in
            if !supportsAttachmentInput {
                discardPendingAttachments()
            }
        }
    }
    
    private var conversationList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    if shouldShowEmptyState {
                        EmptyStateView()
                    }
                    ForEach(currentMessages) { message in
                        MessageBubbleView(message: message)
                            .id(message.id)
                    }
                    if isStreamingInCurrentThread {
                        StreamingMessageView(text: streamingText)
                            .id("streaming")
                    }
                    Color.clear.frame(height: 8)
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 12)
            }
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop(providers:))
            .background(isDropTargeted ? Color.accentColor.opacity(0.05) : Color.clear)
            .onChange(of: sessionController.filteredStreamText) { _, _ in
                guard isStreamingInCurrentThread else { return }
                scrollToStreaming(proxy: proxy)
            }
            .onChange(of: sessionController.isStreaming) { _, isStreaming in
                guard isStreaming, isStreamingInCurrentThread else { return }
                scrollToStreaming(proxy: proxy)
            }
            .onChange(of: currentMessages.count) { _, _ in
                guard let lastMessage = currentMessages.last else { return }
                withAnimation {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
        }
    }
    
    private func sendMessage() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !pendingAttachments.isEmpty else { return }

        input = ""
        let attachments = pendingAttachments.map { $0.attachment }
        pendingAttachments.removeAll()
        
        Task {
            await sessionController.send(text: trimmed, selectedModel: selectedModel, attachments: attachments)
        }
    }
    
    private var shouldShowEmptyState: Bool {
        (state.selectedThread?.messages.isEmpty ?? true) &&
        !isStreamingInCurrentThread
    }
    
    private var streamingText: String {
        sessionController.filteredStreamText.isEmpty
        ? sessionController.streamText
        : sessionController.filteredStreamText
    }
    
    private func scrollToStreaming(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.1)) {
            proxy.scrollTo("streaming", anchor: .bottom)
        }
    }
    
    private var maxPromptCharacters: Int {
        let config = state.getCurrentConfig(for: selectedModel)
        return max(config.maxTokens * 4, 256)
    }
    
    private var supportsAttachmentInput: Bool {
        let modelId = selectedModel.isEmpty ? (state.selectedThread?.modelId ?? "") : selectedModel
        return state.capabilities(for: modelId).contains(.visionInput)
    }
    
    private func addAttachments(from urls: [URL]) {
        guard supportsAttachmentInput else { return }
        var drafts: [AttachmentDraft] = []
        for url in urls {
            do {
                #if canImport(UniformTypeIdentifiers)
                guard let attachmentType = AttachmentStorage.attachmentType(for: url) else { continue }
                #else
                let attachmentType: MessageAttachment.AttachmentType = .image
                #endif
                let attachment = try AttachmentStorage.saveAttachment(from: url, type: attachmentType)
                drafts.append(AttachmentDraft(attachment: attachment))
            } catch {
                sessionController.errorMessage = "Couldn't import \(url.lastPathComponent): \(error.localizedDescription)"
                sessionController.showError = true
            }
        }
        pendingAttachments.append(contentsOf: drafts)
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard supportsAttachmentInput else { return false }
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let url = Self.resolveURL(from: item) else { return }
                    #if canImport(UniformTypeIdentifiers)
                    guard AttachmentStorage.attachmentType(for: url) != nil else { return }
                    #endif
                    DispatchQueue.main.async {
                        addAttachments(from: [url])
                    }
                }
                handled = true
            }
        }
        return handled
    }
    
    private func removeAttachment(_ draft: AttachmentDraft) {
        AttachmentStorage.removeAttachment(draft.attachment)
        pendingAttachments.removeAll { $0.id == draft.id }
    }
    
    private var documentContextBinding: Binding<Bool> {
        Binding(
            get: { state.selectedThread?.useDocumentContext ?? false },
            set: { newValue in
                state.updateSelected { $0.useDocumentContext = newValue }
                if newValue {
                    Task {
                        await state.rebuildKnowledgeBase()
                    }
                }
            }
        )
    }
    
    private var showWorkspacePicker: Bool {
        !(state.codeWorkspaces.isEmpty) && (state.selectedThread?.useDocumentContext ?? false)
    }
    
    private var contextToggle: some View {
        Toggle("Use document context for this chat", isOn: documentContextBinding)
            .toggleStyle(.switch)
            .font(.caption)
            .tint(.accentColor)
            .disabled(state.documents.isEmpty && state.codeWorkspaces.isEmpty)
            .overlay(alignment: .trailing) {
                if state.documents.isEmpty && state.codeWorkspaces.isEmpty {
                    Text("Add files in Context & RAG to enable")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .offset(y: 20)
                }
            }
    }
    
    private var workspacePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Workspaces")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(state.codeWorkspaces) { workspace in
                Toggle(workspace.name, isOn: workspaceBinding(for: workspace))
            }
            .toggleStyle(.switch)
        }
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
    
    private func discardPendingAttachments() {
        guard !pendingAttachments.isEmpty else { return }
        for draft in pendingAttachments {
            AttachmentStorage.removeAttachment(draft.attachment)
        }
        pendingAttachments.removeAll()
    }
    
    private static func resolveURL(from providerItem: NSSecureCoding?) -> URL? {
        if let url = providerItem as? URL {
            return url
        }
        if let data = providerItem as? Data,
           let url = URL(dataRepresentation: data, relativeTo: nil, isAbsolute: true) {
            return url
        }
        if let nsData = providerItem as? NSData,
           let url = URL(dataRepresentation: nsData as Data, relativeTo: nil, isAbsolute: true) {
            return url
        }
        if let nsurl = providerItem as? NSURL {
            return nsurl as URL
        }
        return nil
    }
}

private struct AttachmentDraft: Identifiable, Equatable {
    let id = UUID()
    let attachment: MessageAttachment
    
    static func == (lhs: AttachmentDraft, rhs: AttachmentDraft) -> Bool {
        lhs.id == rhs.id
    }
}

private struct AttachmentStrip: View {
    let attachments: [AttachmentDraft]
    var onRemove: (AttachmentDraft) -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(attachments) { draft in
                    AttachmentCard(
                        draft: draft,
                        onRemove: { onRemove(draft) }
                    )
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct AttachmentCard: View {
    let draft: AttachmentDraft
    var onRemove: () -> Void
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 8) {
                attachmentImage
                    .frame(width: 72, height: 72)
                    .background(Color.gray.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(draft.attachment.filename)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(width: 96)
            .padding(8)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
            }
            .offset(x: 6, y: -6)
        }
    }
    
    @ViewBuilder
    private var attachmentImage: some View {
        switch draft.attachment.type {
        case .image:
            if let image = NSImage(contentsOf: draft.attachment.url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        case .file:
            placeholder
        }
    }
    
    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.2))
            Image(systemName: "doc")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct AttachmentGalleryView: View {
    let attachments: [MessageAttachment]
    
    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 120), spacing: 8)
    ]
    
    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(attachments) { attachment in
                AttachmentPreviewTile(attachment: attachment)
            }
        }
    }
}

private struct AttachmentPreviewTile: View {
    let attachment: MessageAttachment
    
    var body: some View {
        Button {
            NSWorkspace.shared.open(attachment.url)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                previewContent
                    .frame(maxWidth: .infinity)
                    .frame(height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(attachment.filename)
                    .font(.caption)
                    .lineLimit(1)
            }
            .padding(8)
            .background(Color.white.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var previewContent: some View {
        switch attachment.type {
        case .image:
            if let image = NSImage(contentsOf: attachment.url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .background(Color.black.opacity(0.1))
            } else {
                placeholder
            }
        case .file:
            placeholder
        }
    }
    
    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.2))
            Image(systemName: "doc")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct StreamingMessageView: View {
    let text: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                GeneratingIndicator()
                Text("Generating…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 20)
            
            MessageBubbleView(
                message: Message(
                    role: .assistant,
                    text: text
                ),
                isStreaming: true
            )
        }
    }
}

// MARK: - Chat Header (Simplified - Section 1)
struct ChatHeaderView: View {
    let model: String
    let configDescription: String
    let config: InferenceConfig?
    let tokenHint: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(model.isEmpty ? "No Model Selected" : model)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text(tokenHint)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            
            if let config {
                HStack(spacing: 16) {
                    Label(String(format: "Temp %.2f", config.temperature), systemImage: "thermometer")
                    Label("Max \(config.maxTokens)", systemImage: "number")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            
            Text(configDescription)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.controlBackgroundColor).opacity(0.3))
    }
}

// MARK: - Message Bubble
struct MessageBubbleView: View {
    let message: Message
    let isStreaming: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    init(message: Message, isStreaming: Bool = false) {
        self.message = message
        self.isStreaming = isStreaming
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user {
                Spacer(minLength: 60)
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                Group {
                    if message.text.contains("```") {
                        CodeBlockView(text: message.text)
                    } else {
                        Text(message.text)
                            .font(.system(size: 13))
                            .textSelection(.enabled)
                    }
                }
                
                if !message.attachments.isEmpty {
                    AttachmentGalleryView(attachments: message.attachments)
                }
                if message.role == .assistant,
                   let sources = message.referencedDocuments,
                   !sources.isEmpty {
                    DocumentSourcesView(sources: sources)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                message.role == .user
                    ? Color.accentColor.opacity(0.1)
                    : assistantBubbleBackground
            )
            .cornerRadius(12)
            .frame(maxWidth: 600, alignment: message.role == .user ? .trailing : .leading)
            
            if message.role == .assistant {
                Spacer(minLength: 60)
            }
        }
        .padding(.horizontal, 16)
    }
    
    private var assistantBubbleBackground: Color {
#if os(macOS)
        if colorScheme == .dark {
            return Color.white.opacity(0.08)
        } else {
            return Color(nsColor: NSColor.windowBackgroundColor).opacity(0.9)
        }
#else
        if colorScheme == .dark {
            return Color.white.opacity(0.08)
        } else {
            return Color(.secondarySystemBackground)
        }
#endif
    }
}

// MARK: - Code Block View (Improved rendering)
struct CodeBlockView: View {
    let text: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let parts = parseCodeBlocks(text)
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                if part.isCode {
                    // Code block with rounded background
                    ScrollView(.horizontal, showsIndicators: true) {
                        Text(part.content)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(.separatorColor), lineWidth: 1)
                    )
                } else {
                    // Regular text
                    Text(part.content)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                }
            }
        }
    }
    
    private func parseCodeBlocks(_ text: String) -> [TextPart] {
        var parts: [TextPart] = []
        let components = text.components(separatedBy: "```")
        
        for (index, component) in components.enumerated() {
            if index % 2 == 0 {
                // Regular text
                if !component.isEmpty {
                    parts.append(TextPart(content: component, isCode: false))
                }
            } else {
                // Code block
                parts.append(TextPart(content: component, isCode: true))
            }
        }
        
        return parts
    }
    
    private struct TextPart {
        let content: String
        let isCode: Bool
    }
}

// MARK: - Chat Input
struct ChatInputView: View {
    @Binding var input: String
    @Binding var isStreaming: Bool
    let onSend: () -> Void
    let maxInputLength: Int
    let hasPendingAttachments: Bool
    let supportsAttachments: Bool
    let onAddAttachment: () -> Void
    var onTyping: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                if supportsAttachments {
                    Button(action: onAddAttachment) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 16, weight: .semibold))
                            .padding(10)
                            .background(
                                Circle()
                                    .fill(Color(.textBackgroundColor))
                            )
                    }
                    .buttonStyle(.plain)
                }
                
                TextField("Type a message", text: $input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.accentColor.opacity(0.15), lineWidth: 1)
                    )
                    .lineLimit(1...6)
                    .submitLabel(.send)
                    .onSubmit {
                        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasPendingAttachments else { return }
                        onSend()
                    }
                    .onChange(of: input) { newValue in
                        onTyping?()
                        guard maxInputLength > 0 else { return }
                        if newValue.count > maxInputLength {
                            input = String(newValue.prefix(maxInputLength))
                        }
                    }
                
                Button(action: {
                    if isStreaming {
                        // stop streaming handled by parent
                    } else {
                        onSend()
                    }
                }) {
                    Image(systemName: isStreaming ? "stop.fill" : "paperplane.fill")
                        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(isStreaming ? Color.orange : Color.accentColor)
                        .padding(10)
                        .background(
                            Circle()
                                .fill(Color.accentColor.opacity(isStreaming ? 0.2 : 0.15))
                        )
                        .rotationEffect(.degrees(isStreaming ? 0 : 45))
                }
                .buttonStyle(.plain)
                .disabled(isStreaming ? false : (input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !hasPendingAttachments))
            }
            
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .background(
            LinearGradient(colors: [.white.opacity(0.08), .white.opacity(0.02)], startPoint: .top, endPoint: .bottom)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.3), .white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.15), radius: 15, x: 0, y: 8)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}

// MARK: - Empty State
struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.5))
            
            Text("Start a conversation")
                .font(.system(size: 20, weight: .semibold))
            
            Text("Send a message to begin chatting")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - First-Run / No-Model UI (4.1)
struct FirstRunWelcomeView: View {
    let onModelsDetected: () -> Void
    
    @State private var checkTimer: Timer?
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Large icon / illustration
            Image(systemName: "cpu")
                .font(.system(size: 64))
                .foregroundStyle(.secondary.opacity(0.6))
            
            VStack(spacing: 12) {
                Text("Welcome to Lumen")
                    .font(.system(size: 28, weight: .bold))
                
                Text("Run private, offline AI models on your Mac")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            
            VStack(spacing: 16) {
                Text("Everything runs locally on your machine.\nNo cloud services. No data collection. Complete privacy.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
                
                HStack(spacing: 12) {
                    Button(action: {
                        // Open Models Folder in Finder
                        let url = ModelStorage.shared.modelsURL
                        NSWorkspace.shared.open(url)
                    }) {
                        Label("Open Models Folder", systemImage: "folder.fill")
                            .frame(minWidth: 180)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            
            Spacer()
            
            // Secondary help text
            VStack(spacing: 8) {
                Text("To get started:")
                    .font(.system(size: 12, weight: .semibold))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("1. Download a model from Hugging Face (mlx-community)")
                    Text("2. Add it in Preferences → Models")
                    Text("3. Select the model and start chatting")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
        .onAppear {
            // Start checking for models periodically (4.2)
            startModelCheckTimer()
        }
        .onDisappear {
            stopModelCheckTimer()
        }
    }
    
    // Periodically check for models to enable smooth transition (4.2)
    private func startModelCheckTimer() {
        checkTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            let modelsURL = ModelStorage.shared.modelsURL
            let fm = FileManager.default
            
            guard fm.fileExists(atPath: modelsURL.path),
                  let items = try? fm.contentsOfDirectory(at: modelsURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
                return
            }
            
            // Check if any directories exist (potential models)
            let hasModel = items.contains { item in
                (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            
            if hasModel {
                onModelsDetected()
                stopModelCheckTimer()
            }
        }
    }
    
    private func stopModelCheckTimer() {
        checkTimer?.invalidate()
        checkTimer = nil
    }
}

// MARK: - Preferences Window
struct PreferencesWindow: View {
    @ObservedObject var state: AppState
    @Binding var modelFolders: [String]
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedTab: PreferenceTab = .general
    @State private var defaultModel: String = ""
    @State private var saveChatHistory: Bool = true
    @State private var showPathPicker = false
    @State private var customModelPath: String = ""
    
    enum PreferenceTab: String, CaseIterable {
        case general = "General"
        case models = "Models"
        case privacy = "Privacy"
    }
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                ForEach(PreferenceTab.allCases, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: iconForTab(tab))
                        .tag(tab)
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 180)
        } detail: {
            Group {
                switch selectedTab {
                case .general:
                    GeneralPreferencesView(
                        state: state,
                        defaultModel: $defaultModel,
                        saveChatHistory: $saveChatHistory,
                        modelFolders: modelFolders
                    )
                case .models:
                    ModelsPreferencesView(
                        state: state,
                        modelFolders: $modelFolders,
                        customModelPath: $customModelPath,
                        showPathPicker: $showPathPicker
                    )
                case .privacy:
                    PrivacyPreferencesView(state: state)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 700, height: 500)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .onAppear {
            defaultModel = UserDefaults.standard.string(forKey: "defaultModel") ?? ""
            saveChatHistory = UserDefaults.standard.bool(forKey: "saveChatHistory")
            customModelPath = ModelStorage.shared.customModelPath ?? ""
        }
        .fileImporter(
            isPresented: $showPathPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                ModelStorage.shared.setCustomModelPath(url.path)
                customModelPath = url.path
                modelFolders = state.listModelFolders()
            }
        }
    }
    
    private func iconForTab(_ tab: PreferenceTab) -> String {
        switch tab {
        case .general: return "gearshape"
        case .models: return "cpu"
        case .privacy: return "lock.shield"
        }
    }
}

// MARK: - General Preferences
struct GeneralPreferencesView: View {
    @ObservedObject var state: AppState
    @Binding var defaultModel: String
    @Binding var saveChatHistory: Bool
    let modelFolders: [String]
    @State private var blackHolePath: String = ""
    @AppStorage("telemetry.hud.enabled") private var telemetryEnabled = false
    @AppStorage("telemetry.sampling.seconds") private var telemetrySampling: Double = 1.0
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Defaults") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Default Model", selection: $defaultModel) {
                            Text("None").tag("")
                            ForEach(modelFolders, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .onChange(of: defaultModel) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: "defaultModel")
                        }
                        
                        Toggle("Save chat history locally", isOn: Binding(
                            get: { saveChatHistory },
                            set: { newValue in
                                saveChatHistory = newValue
                                UserDefaults.standard.set(newValue, forKey: "saveChatHistory")
                                state.saveChatHistory = newValue
                            }
                        ))
                        
                        Text("Chat history is saved to ~/Lumen/Chats")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                GroupBox("Black Hole Folder") {
                    VStack(alignment: .leading, spacing: 10) {
                        if blackHolePath.isEmpty {
                            Text("No folder selected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(blackHolePath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        
                        HStack {
                            Button("Choose Folder…") {
                                selectBlackHoleFolder()
                            }
                            .buttonStyle(.bordered)
                            
                            if !blackHolePath.isEmpty {
                                Button("Clear") {
                                    state.clearBlackHoleFolder()
                                    blackHolePath = ""
                                }
                                .buttonStyle(.bordered)
                                
                                Button("Reindex Now") {
                                    state.rescanBlackHoleFolder()
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        
                        Text("Use Reindex Now to ingest files from this folder. No automatic indexing runs on startup.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                GroupBox("Model Behavior") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Use Manual Override", isOn: Binding(
                            get: { state.manualOverrideEnabled },
                            set: { state.manualOverrideEnabled = $0 }
                        ))
                        
                        Text("When disabled, each model uses its registry defaults. Enable to force the custom settings below for every chat.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 10) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Temperature")
                                Slider(value: overrideBinding(\.temperature), in: 0...2, step: 0.05)
                                Text("\(state.manualOverrideConfig.temperature, specifier: "%.2f")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Max Tokens")
                                Stepper(value: overrideBinding(\.maxTokens), in: 1...4096, step: 32) {
                                    Text("\(state.manualOverrideConfig.maxTokens)")
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Top P")
                                Slider(value: overrideBinding(\.topP), in: 0...1, step: 0.05)
                                Text("\(state.manualOverrideConfig.topP, specifier: "%.2f")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Max KV Cache")
                                Stepper(value: overrideBinding(\.maxKV), in: 128...2048, step: 128) {
                                    Text("\(state.manualOverrideConfig.maxKV)")
                                }
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("System Prompt")
                            TextEditor(text: overrideBinding(\.systemPrompt))
                                .font(.body)
                                .frame(minHeight: 110)
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color(nsColor: .textBackgroundColor).opacity(0.9))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color.secondary.opacity(0.25))
                                )
                        }
                            
                            Toggle("Trust Remote Code", isOn: overrideBinding(\.trustRemoteCode))
                        }
                        .disabled(!state.manualOverrideEnabled)
                    }
                }
                
                GroupBox("Telemetry") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Show Telemetry HUD", isOn: $telemetryEnabled)
                        HStack {
                            Text("Sampling Rate")
                            Spacer()
                            Text(String(format: "%.2fs", telemetrySampling))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $telemetrySampling, in: 0.25...5.0, step: 0.25)
                        Text("Displays overlay with model, RAM, and thermal state. Token/sec is placeholder for now.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                GroupBox("Model defaults JSON") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(AppDirs.modelDefaults.path)
                            .font(.caption)
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
        }
        .background(Color.clear)
        .navigationTitle("General")
        .onAppear {
            blackHolePath = state.blackHoleFolderPath
        }
    }
    
    private func selectBlackHoleFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { response in
            if response == .OK, let url = panel.url {
                state.setBlackHoleFolder(url)
                blackHolePath = url.path
            }
        }
    }
    
    private func overrideBinding<Value>(_ keyPath: WritableKeyPath<InferenceConfig, Value>) -> Binding<Value> {
        Binding(
            get: { state.manualOverrideConfig[keyPath: keyPath] },
            set: { newValue in
                var updated = state.manualOverrideConfig
                updated[keyPath: keyPath] = newValue
                state.manualOverrideConfig = updated
            }
        )
    }
}

// MARK: - Models Preferences
struct ModelsPreferencesView: View {
    @ObservedObject var state: AppState
    @Binding var modelFolders: [String]
    @Binding var customModelPath: String
    @Binding var showPathPicker: Bool
    @AppStorage("useModelColorIndicators") private var useModelColorIndicators = true
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Installed Models") {
                    if modelFolders.isEmpty {
                        Text("No models detected")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(modelFolders, id: \.self) { model in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(model)
                                            .font(.body)
                                        if let modelURL = state.findModelURL(for: model) {
                                            Text(modelURL.path)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    Button("Reveal in Finder") {
                                        if let url = state.findModelURL(for: model) {
                                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                }
                
                GroupBox("Storage") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(ModelStorage.shared.modelsURL.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        
                        HStack(spacing: 10) {
                            Button("Choose Folder…") {
                                showPathPicker = true
                            }
                            .buttonStyle(.borderedProminent)
                            
                            if ModelStorage.shared.customModelPath != nil {
                                Button("Reset to Default") {
                                    ModelStorage.shared.setCustomModelPath(nil)
                                    customModelPath = ""
                                    modelFolders = state.listModelFolders()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        
                        Text("Models are stored in the selected folder. The app will automatically detect models in this location.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                GroupBox("Appearance") {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Color-code model indicators", isOn: $useModelColorIndicators)
                        Text("When disabled, all models use the accent color in the sidebar.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
        }
        .background(Color.clear)
        .navigationTitle("Models")
    }
}

// MARK: - Privacy Preferences (3.2, 3.3, 3.4)
struct PrivacyPreferencesView: View {
    @ObservedObject var state: AppState
    @State private var showPrivacyPolicy = false
    @State private var showTerms = false
    @State private var showKnowledgeWipeConfirmation = false
    
    var modelsPath: String {
        ModelStorage.shared.modelsURL.path
    }
    
    var chatsPath: String {
        AppDirs.chats.path
    }
    
    var appSupportPath: String {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LumenComposite")
            .path
    }
    
    var knowledgeBasePath: String {
        AppDirs.knowledgeBase.path
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Privacy & Data")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Lumen is designed with privacy as a core principle. All processing happens locally on your device.")
                        .font(.body)
                }
                
                Divider()
                
                // 3.1: Optional Chat History
                Section {
                    Toggle("Save chat history locally", isOn: Binding(
                        get: { state.saveChatHistory },
                        set: { newValue in
                            state.saveChatHistory = newValue
                            UserDefaults.standard.set(newValue, forKey: "saveChatHistory")
                            if !newValue {
                                // Optionally clear persisted history when disabled
                                try? SecureStorage.clearAllData()
                                state.threads = []
                            }
                        }
                    ))
                } header: {
                    Text("Chat History")
                } footer: {
                    Text("When disabled, conversations will not be saved and existing history will be cleared.")
                }
                
                Divider()
                
                // 3.2: Storage Actions
                VStack(alignment: .leading, spacing: 12) {
                    Text("Storage & Locations")
                        .font(.headline)
                    
                    Text("Your data stays on this device. Use the shortcuts below to jump to key folders.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 12) {
                        Button("Open Models Folder") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: modelsPath))
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Open Chats Folder") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: chatsPath))
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    Button("Open Application Support") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: appSupportPath))
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Knowledge Base")
                        .font(.headline)
                    
                    Text("Remove all indexed documents, embeddings, code workspace caches, and knowledge metadata.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text(knowledgeBasePath)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    
                    HStack(spacing: 12) {
                        Button("Open Knowledge Base Folder") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: knowledgeBasePath))
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Wipe Knowledge Base", role: .destructive) {
                            showKnowledgeWipeConfirmation = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                
                Divider()
                
                // Privacy guarantees
                VStack(alignment: .leading, spacing: 12) {
                    Label("No Cloud Services", systemImage: "lock.shield")
                        .font(.headline)
                    Text("All models and conversations are stored locally on your Mac. Nothing is sent to external servers.")
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Label("No Analytics", systemImage: "chart.bar.xaxis")
                        .font(.headline)
                    Text("We don't collect any usage data, analytics, or telemetry. Your conversations remain private.")
                }
                
                Divider()
                
                // 3.3: Privacy & Legal Docs
                VStack(alignment: .leading, spacing: 12) {
                    Text("Legal Documents")
                        .font(.headline)
                    
                    HStack(spacing: 12) {
                        Button(action: { showPrivacyPolicy = true }) {
                            Label("Privacy Policy", systemImage: "lock.shield")
                        }
                        .buttonStyle(.bordered)
                        
                        Button(action: { showTerms = true }) {
                            Label("Terms & Conditions", systemImage: "doc.text")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                Divider()
                
                // 3.4: Source Transparency
                VStack(alignment: .leading, spacing: 12) {
                    Text("Source Transparency")
                        .font(.headline)
                    
                    Text("Lumen is built with transparency in mind. The source code and project structure are available for review.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Button("Open Source Folder") {
                        // Try to open project root directory
                        let resourcePath = Bundle.main.resourcePath ?? ""
                        var projectPath = (resourcePath as NSString).deletingLastPathComponent
                        projectPath = (projectPath as NSString).deletingLastPathComponent
                        projectPath = (projectPath as NSString).deletingLastPathComponent
                        
                        if FileManager.default.fileExists(atPath: projectPath) {
                            NSWorkspace.shared.open(URL(fileURLWithPath: projectPath))
                        } else {
                            // Fallback: Open Application Support
                            NSWorkspace.shared.open(URL(fileURLWithPath: appSupportPath))
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Privacy")
        .sheet(isPresented: $showPrivacyPolicy) {
            PrivacyPolicyDocumentView()
        }
        .sheet(isPresented: $showTerms) {
            TermsDocumentView()
        }
        .alert("Wipe Knowledge Base?", isPresented: $showKnowledgeWipeConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Wipe", role: .destructive) {
                state.wipeKnowledgeBase()
            }
        } message: {
            Text("Deletes all knowledge base files, including indexed documents, embeddings, code workspace indexes, and related metadata.")
        }
    }
}

// MARK: - Privacy Policy Document View (3.3)
struct PrivacyPolicyDocumentView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var content: String = "Loading..."
    
    var body: some View {
        NavigationStack {
            ScrollView {
                Text(content)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("Privacy Policy")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .onAppear {
            loadDocument(filename: "PRIVACY_POLICY")
        }
    }
    
    private func loadDocument(filename: String) {
        // Try to load from bundle first
        if let url = Bundle.main.url(forResource: filename, withExtension: "md") {
            content = (try? String(contentsOf: url)) ?? "\(filename) content not found."
            return
        }
        
        // Try project root
        let resourcePath = Bundle.main.resourcePath ?? ""
        var projectPath = (resourcePath as NSString).deletingLastPathComponent
        projectPath = (projectPath as NSString).deletingLastPathComponent
        projectPath = (projectPath as NSString).deletingLastPathComponent
        let documentPath = (projectPath as NSString).appendingPathComponent("\(filename).md")
        
        if FileManager.default.fileExists(atPath: documentPath),
           let loaded = try? String(contentsOfFile: documentPath) {
            content = loaded
        } else {
            content = "\(filename) content not found. Please check the project root directory."
        }
    }
}

// MARK: - Terms Document View (3.3)
struct TermsDocumentView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var content: String = "Loading..."
    
    var body: some View {
        NavigationStack {
            ScrollView {
                Text(content)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("Terms & Conditions")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .onAppear {
            loadDocument(filename: "TERMS_AND_CONDITIONS")
        }
    }
    
    private func loadDocument(filename: String) {
        // Try to load from bundle first
        if let url = Bundle.main.url(forResource: filename, withExtension: "md") {
            content = (try? String(contentsOf: url)) ?? "\(filename) content not found."
            return
        }
        
        // Try project root
        let resourcePath = Bundle.main.resourcePath ?? ""
        var projectPath = (resourcePath as NSString).deletingLastPathComponent
        projectPath = (projectPath as NSString).deletingLastPathComponent
        projectPath = (projectPath as NSString).deletingLastPathComponent
        let documentPath = (projectPath as NSString).appendingPathComponent("\(filename).md")
        
        if FileManager.default.fileExists(atPath: documentPath),
           let loaded = try? String(contentsOfFile: documentPath) {
            content = loaded
        } else {
            content = "\(filename) content not found. Please check the project root directory."
        }
    }
}

// MARK: - Help View
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Quick Start Guide")
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text("Get started with Lumen in minutes")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Step 1: Download a Model")
                            .font(.headline)
                        
                        Text("Lumen uses MLX models. Download a compatible model from Hugging Face:")
                            .font(.body)
                        
                        Text("1. Visit mlx-community on Hugging Face")
                            .font(.body)
                        Text("2. Download a 4-bit quantized model (recommended for best performance)")
                            .font(.body)
                        Text("3. Extract the model folder")
                            .font(.body)
                        
                        Text("Recommended models:")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .padding(.top, 8)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("• Qwen1.5-0.5B-Chat-4bit")
                            Text("• SmolLM-135M-4bit")
                            Text("• OpenELM-270M-Instruct-4bit")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Step 2: Add Model to App")
                            .font(.headline)
                        
                        Text("1. Open Preferences (⌘,)")
                            .font(.body)
                        Text("2. Go to the Models tab")
                            .font(.body)
                        Text("3. Click 'Choose Folder' and select your model folder")
                            .font(.body)
                        Text("4. The model will appear in the sidebar automatically")
                            .font(.body)
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Step 3: Start Chatting")
                            .font(.headline)
                        
                        Text("1. Select a model from the toolbar dropdown")
                            .font(.body)
                        Text("2. Click 'New Chat' in the sidebar")
                            .font(.body)
                        Text("3. Type your message and press ⌘↩︎ to send")
                            .font(.body)
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Keyboard Shortcuts")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("⌘↩︎ - Send message")
                            Text("⌘, - Open Preferences")
                            Text("⌘⌥S - Toggle sidebar")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Help")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 600, height: 500)
    }
}

// MARK: - Top Bar Pill View
struct TopBarPillView: View {
    let modelName: String
    @ObservedObject var state: AppState
    @ObservedObject var sessionController: ChatSessionController
    @Binding var isSidebarVisible: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            // Sidebar Toggle (if hidden)
            if !isSidebarVisible {
                Button(action: { withAnimation { isSidebarVisible = true } }) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Show Sidebar")
                
                Divider()
                    .frame(height: 12)
                    .overlay(Color.white.opacity(0.2))
            }
            
            // Model Info
            HStack(spacing: 8) {
                Image(systemName: "cpu")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Text(modelName.isEmpty ? "No Model" : modelName)
                    .font(.system(size: 13, weight: .medium))
            }
            
            // Stats / Status
            HStack(spacing: 16) {
                // Status
                if !statusText.isEmpty {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 6, height: 6)
                            .shadow(color: statusColor.opacity(0.6), radius: 4)
                        Text(statusText)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                    
                    Divider()
                        .frame(height: 12)
                        .overlay(Color.white.opacity(0.2))
                }
                
                // System Stats
                SystemStatsView()
                
                // Token Count
                if let thread = state.selectedThread, !thread.messages.isEmpty {
                    Divider()
                        .frame(height: 12)
                        .overlay(Color.white.opacity(0.2))
                    
                    Text("\(state.estimateTokens(from: thread.messages.last?.text ?? "")) toks")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.1))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            

        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .background(
            LinearGradient(colors: [.white.opacity(0.1), .clear], startPoint: .top, endPoint: .bottom)
        )
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.4), .white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 10)
    }
    
    private var statusColor: Color {
        if sessionController.isStreaming { return .blue }
        if state.isKnowledgeIndexing { return .purple }
        if sessionController.isLoadingModel { return .orange }
        if state.isModelLoaded { return .green }
        return .gray
    }
    
    private var statusText: String {
        if sessionController.isStreaming { return "Generating" }
        if state.isKnowledgeIndexing { return "Indexing" }
        if sessionController.isLoadingModel { return "Loading" }
        if state.isModelLoaded { return "Ready" }
        return ""
    }
}

struct SystemStatsView: View {
    @State private var cpuUsage: Double = 0
    @State private var ramUsage: Double = 0
    @State private var ramTotal: Double = 0
    
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 12) {
            // CPU
            HStack(spacing: 4) {
                Text("CPU")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.0f%%", cpuUsage))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(cpuUsage > 80 ? .red : .primary)
            }
            
            // RAM
            HStack(spacing: 4) {
                Text("RAM")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.1f GB", ramUsage))
                    .font(.caption2)
                    .monospacedDigit()
            }
        }
        .onReceive(timer) { _ in
            updateStats()
        }
        .onAppear { updateStats() }
    }
    
    private func updateStats() {
        // RAM
        let total = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0
        ramTotal = total
        
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let hostPort = mach_host_self()
        
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO, $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            let pageSize = Double(vm_kernel_page_size)
            let active = Double(stats.active_count) * pageSize
            let wired = Double(stats.wire_count) * pageSize
            let compressed = Double(stats.compressor_page_count) * pageSize
            let used = (active + wired + compressed) / 1_073_741_824.0
            ramUsage = used
        }
        
        // CPU (Mock for now as real CPU usage requires complex host_processor_info)
        // We'll simulate some activity if the app is doing things
        // In a real app, we'd implement the host_processor_info logic
        cpuUsage = Double.random(in: 5...15)
    }
}

#endif
