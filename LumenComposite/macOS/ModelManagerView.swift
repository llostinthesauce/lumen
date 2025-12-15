#if os(macOS)
import SwiftUI
import AppKit

struct ModelManagerView: View {
    @ObservedObject var state: AppState
    @Binding var modelFolders: [String]
    var onRefresh: () -> Void = {}
    
    @State private var models: [ManagedModel] = []
    @State private var isLoading: Bool = false
    @State private var error: String?
    @State private var lastRefreshed = Date()
    @State private var showCatalog = false
    @State private var downloadURL: URL?
    @State private var downloadProgress: Double = 0
    @State private var isDownloading = false
    @State private var downloadStatus: String?
    
    private let ramBytes = ProcessInfo.processInfo.physicalMemory
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            
            if let error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
            
            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Scanning models…")
                        .foregroundStyle(.secondary)
                }
            }
            
            if let downloadStatus {
                HStack {
                    if isDownloading {
                        ProgressView(value: downloadProgress)
                            .frame(width: 120)
                    }
                    Text(downloadStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if isDownloading {
                        Button {
                            downloadURL = nil
                            isDownloading = false
                        } label: {
                            Label("Cancel", systemImage: "xmark")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            
            if models.isEmpty && !isLoading {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No models detected.")
                        .font(.headline)
                    Text("Add MLX checkpoints to your configured model folder, then tap Refresh.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(models) { model in
                            ModelCardView(
                                model: model,
                                ramBytes: ramBytes,
                                isCurrent: state.currentModelURL == model.url && state.isModelLoaded,
                                onLoad: { load(model: model) },
                                onUnload: unloadCurrent
                            )
                        }
                    }
                    .padding(.top, 4)
                }
            }
            
            Spacer()
        }
        .padding(24)
        .onAppear {
            refreshModels()
        }
    }
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Model Manager")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Manage locally installed MLX checkpoints. Load/unload models and check memory fit.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            Spacer()
            HStack(spacing: 8) {
                Button {
                    refreshModels()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                
                Button {
                    onRefresh()
                    refreshModels()
                } label: {
                    Label("Rescan Folders", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                
                Button {
                    showCatalog = true
                } label: {
                    Label("Browse Hugging Face", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
            }
        }
        .sheet(isPresented: $showCatalog) {
            ModelDiscoveryView(
                onSelectModel: { model in
                    startDownload(modelId: model.modelId)
                }
            )
            .frame(minWidth: 720, minHeight: 520)
        }
    }
    
    private func refreshModels() {
        isLoading = true
        error = nil
        let currentFolders = modelFolders
        Task.detached {
            var built: [ManagedModel] = []
            for name in currentFolders {
                let url = await MainActor.run { state.findModelURL(for: name) }
                let size = url.flatMap { folderSize($0) }
                let format = url.map { ModelFormatDetector.detectFormat(at: $0) } ?? .unknown
                let validation = url.map { ModelValidator.validate(at: $0) }
                let fit = fitStatus(for: size)
                let info = ManagedModel(
                    id: name,
                    url: url,
                    sizeBytes: size,
                    format: format,
                    fit: fit,
                    validationIssues: validation?.issues.count ?? 0,
                    validationWarnings: validation?.warnings.count ?? 0
                )
                built.append(info)
            }
            built.sort { $0.id.lowercased() < $1.id.lowercased() }
            await MainActor.run {
                self.models = built
                self.isLoading = false
                self.lastRefreshed = Date()
            }
        }
    }
    
    private func fitStatus(for size: Int64?) -> FitStatus {
        guard let size, ramBytes > 0 else { return .unknown }
        let ratio = Double(size) / Double(ramBytes)
        if ratio <= 0.25 { return .good }
        if ratio <= 0.5 { return .ok }
        return .heavy
    }
    
    private func load(model: ManagedModel) {
        guard let _ = model.url else {
            error = "Model path not found."
            return
        }
        Task {
            isLoading = true
            error = nil
            let threadId = state.getOrCreateThread(for: model.id)
            state.selectedThreadID = threadId
            do {
                await state.unloadCurrentModel()
                try await state.loadModel(model.id)
                await MainActor.run {
                    state.updateSelected { thread in
                        thread.modelId = model.id
                        thread.config = state.getCurrentConfig(for: model.id)
                    }
                }
            } catch {
                await MainActor.run {
                    self.error = "Load failed: \(error.localizedDescription)"
                }
            }
            await MainActor.run {
                isLoading = false
                refreshModels()
            }
        }
    }
    
    private func startDownload(modelId: String) {
        guard let url = URL(string: "https://huggingface.co/\(modelId)/resolve/main/") else {
            error = "Invalid model URL."
            return
        }
        downloadURL = url
        isDownloading = true
        downloadStatus = "Fetching \(modelId)…"
        
        // We attempt to download all .safetensors and config/tokenizer files in one pass via snapshot API.
        Task.detached {
            do {
                try await HuggingFaceDownloader.downloadRepository(modelId: modelId) { progress, status in
                    Task { @MainActor in
                        self.downloadProgress = progress
                        self.downloadStatus = status
                    }
                }
                await MainActor.run {
                    self.downloadStatus = "Downloaded \(modelId). Refreshing…"
                    self.onRefresh()
                    self.refreshModels()
                }
            } catch {
                await MainActor.run {
                    self.error = "Download failed: \(error.localizedDescription)"
                }
            }
            await MainActor.run {
                self.isDownloading = false
            }
        }
    }
    
    private func unloadCurrent() {
        Task {
            isLoading = true
            await state.unloadCurrentModel()
            await MainActor.run {
                isLoading = false
                refreshModels()
            }
        }
    }
}

// MARK: - Model Card

private struct ModelCardView: View {
    let model: ManagedModel
    let ramBytes: UInt64
    let isCurrent: Bool
    var onLoad: () -> Void
    var onUnload: () -> Void
    @State private var isHovering = false
    
    private var fitText: String {
        switch model.fit {
        case .good: return "Fits (Good)"
        case .ok: return "Fits (Moderate)"
        case .heavy: return "Heavy (May not fit)"
        case .unknown: return "Unknown fit"
        }
    }
    
    private var fitColor: Color {
        switch model.fit {
        case .good: return .green
        case .ok: return .orange
        case .heavy: return .red
        case .unknown: return .gray
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(model.id)
                            .font(.headline)
                            .lineLimit(1)
                        if isCurrent {
                            Label("Loaded", systemImage: "bolt.fill")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15))
                                .foregroundStyle(.green)
                                .cornerRadius(6)
                        }
                    }
                    HStack(spacing: 12) {
                        Label(model.sizeBytes.map { humanReadable($0) } ?? "Size: ?", systemImage: "externaldrive")
                            .font(.caption)
                        Label("Format: \(ModelFormatDetector.formatName(model.format))", systemImage: "doc.text")
                            .font(.caption)
                        Label(fitText, systemImage: "gauge.medium")
                            .font(.caption)
                            .foregroundStyle(fitColor)
                        if model.validationIssues > 0 {
                            Label("\(model.validationIssues) issue(s)", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                        } else if model.validationWarnings > 0 {
                            Label("\(model.validationWarnings) warning(s)", systemImage: "exclamationmark.circle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    Button(action: onLoad) {
                        Label("Load", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isCurrent)
                    
                    Button(action: onUnload) {
                        Label("Unload", systemImage: "eject.fill")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!isCurrent)
                }
            }
            
            if let url = model.url {
                HStack {
                    Text(url.path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Label("Reveal", systemImage: "folder")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(isHovering ? 0.2 : 0.05), lineWidth: 1)
        )
        .shadow(color: .black.opacity(isHovering ? 0.08 : 0), radius: 4, x: 0, y: 2)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Helpers

private struct ManagedModel: Identifiable {
    let id: String
    let url: URL?
    let sizeBytes: Int64?
    let format: ModelFormat
    let fit: FitStatus
    let validationIssues: Int
    let validationWarnings: Int
}

private enum FitStatus {
    case good, ok, heavy, unknown
}

private func folderSize(_ url: URL) -> Int64 {
    var total: Int64 = 0
    if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) {
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
    }
    return total
}

private func humanReadable(_ bytes: Int64) -> String {
    let units: [String] = ["B", "KB", "MB", "GB", "TB"]
    var value = Double(bytes)
    var idx = 0
    while value >= 1024 && idx < units.count - 1 {
        value /= 1024
        idx += 1
    }
    return String(format: "%.1f %@", value, units[idx])
}
#endif
