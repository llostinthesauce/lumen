import SwiftUI

public struct ManageModelsView: View {
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
    
    public init(state: AppState, selectedModel: Binding<String>, onRefresh: @escaping () -> Void) {
        self.state = state
        self._selectedModel = selectedModel
        self.onRefresh = onRefresh
    }
    
    public var body: some View {
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
                        state.currentEngineName = "MLX"
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
struct CuratedModel: Identifiable {
    var id: String { folderName }
    let modelId: String
    let folderName: String
    let displayName: String
    let blurb: String
}
#endif
