// macOS-only UI for managing local context; excluded on iOS builds.
#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContextManagerView: View {
    @ObservedObject var state: AppState
    @State private var isDropping = false
    @State private var isImporting = false
    @State private var error: String?
    @State private var showFilePicker = false
    @State private var showBlackHolePicker = false
    @State private var searchText = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            
            if let error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
            
            controls
            
            contextToggle
            
            blackHoleSection
            
            dropZone
            
            documentsList
            
            recentHits
            
            Spacer()
        }
        .padding(24)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                importDocuments(urls: urls)
            case .failure(let err):
                error = err.localizedDescription
            }
        }
    }
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Context & RAG")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Add local files for retrieval. Drag & drop or pick from Finder.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            Spacer()
            if state.isKnowledgeIndexing {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Indexing…")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
    }
    
    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    showFilePicker = true
                } label: {
                    Label("Choose Files…", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.borderedProminent)
            }
            
            if !state.isEmbeddingModelLoaded {
                Text("Embedding model is initializing...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var contextToggle: some View {
        Toggle("Use context in current chat", isOn: Binding(
            get: { state.selectedThread?.useDocumentContext ?? false },
            set: { newValue in
                state.updateSelected { $0.useDocumentContext = newValue }
                if newValue {
                    Task { await state.rebuildKnowledgeBase() }
                }
            }
        ))
        .toggleStyle(.switch)
        .font(.subheadline)
    }
    
    private var blackHoleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Black Hole Folder")
                    .font(.headline)
                Spacer()
                if !state.blackHoleFolderPath.isEmpty {
                    Button {
                        state.rescanBlackHoleFolder()
                    } label: {
                        Label("Reindex", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                    Button(role: .destructive) {
                        state.clearBlackHoleFolder()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            }
            
            HStack(spacing: 8) {
                if state.blackHoleFolderPath.isEmpty {
                    Text("No folder selected.")
                        .foregroundStyle(.secondary)
                } else {
                    Text(state.blackHoleFolderPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Button {
                    chooseBlackHoleFolder()
                } label: {
                    Label(state.blackHoleFolderPath.isEmpty ? "Choose…" : "Change…", systemImage: "folder.badge.gear")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
    
    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(isDropping ? Color.accentColor : Color.primary.opacity(0.1), style: StrokeStyle(lineWidth: 2, dash: [6]))
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isDropping ? Color.accentColor.opacity(0.08) : Color.clear)
            )
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("Drag & drop files here to add to context")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Supported: txt, md, rtf, pdf, doc/x, html, images for vision models")
                        .font(.caption)
                        .foregroundStyle(.secondary.opacity(0.8))
                }
                .padding()
            )
            .frame(height: 140)
            .onDrop(of: [.fileURL], isTargeted: $isDropping) { providers in
                handleDrop(providers: providers)
            }
    }
    
    private var documentsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Documents (\(state.documents.count))")
                    .font(.headline)
                Spacer()
                TextField("Search documents", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
            }
            
            if state.documents.isEmpty {
                Text("No documents added yet.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(filteredDocuments) { doc in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(doc.title)
                                        .font(.body)
                                    Text(doc.kind.rawValue.capitalized)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    NSWorkspace.shared.open(doc.fileURL)
                                } label: {
                                    Image(systemName: "eye")
                                }
                                .buttonStyle(.borderless)
                                Button(role: .destructive) {
                                    state.removeUserDocument(doc.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(10)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(8)
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
    }

    private var recentHits: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Context Hits")
                .font(.headline)
            if let hits = lastReferencedDocs, !hits.isEmpty {
                ForEach(hits, id: \.self) { hit in
                    Text("• \(hit)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No referenced documents yet.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
        }
    }
    
    // MARK: - Actions
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let url = resolveURL(from: item) else { return }
                    Task { @MainActor in
                        importDocuments(urls: [url])
                    }
                }
                handled = true
            }
        }
        return handled
    }
    
    private func resolveURL(from providerItem: NSSecureCoding?) -> URL? {
        if let url = providerItem as? URL { return url }
        if let data = providerItem as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }
        if let nsData = providerItem as? NSData {
            return URL(dataRepresentation: nsData as Data, relativeTo: nil)
        }
        if let nsurl = providerItem as? NSURL {
            return nsurl as URL
        }
        return nil
    }
    
    private func importDocuments(urls: [URL]) {
        guard !urls.isEmpty else { return }
        isImporting = true
        error = nil
        let docs = state.importUserDocuments(from: urls)
        isImporting = false
        if docs.isEmpty {
            error = "No supported documents were imported."
        } else {
            if state.isEmbeddingModelLoaded {
                startIndexing()
            }
        }
    }
    

    
    private func startIndexing() {
        guard state.isEmbeddingModelLoaded else {
            error = "Load an embedding model first."
            return
        }
        Task {
            await state.rebuildKnowledgeBase()
        }
    }
    
    private func chooseBlackHoleFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            state.setBlackHoleFolder(url)
        }
    }
    
    private var filteredDocuments: [UserDocument] {
        guard !searchText.isEmpty else { return state.documents }
        return state.documents.filter { doc in
            doc.title.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private var lastReferencedDocs: [String]? {
        guard let messages = state.selectedThread?.messages else { return nil }
        let assistant = messages.last { $0.role == .assistant && $0.referencedDocuments != nil }
        return assistant?.referencedDocuments
    }
}
#endif
