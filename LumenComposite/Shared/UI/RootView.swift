import SwiftUI
import UniformTypeIdentifiers
import Combine
#if os(macOS)
import AppKit
#else
import UIKit
#endif

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
        .toolbar {
            macToolbarContent
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
