#if canImport(MLXEmbedders)
import Foundation
import os

extension AppState {
    /// Ensure an embedding backend is loaded; lazy-creates client, store, and indexers.
    /// Ensure an embedding backend is loaded; lazy-creates client, store, and indexers.
    @discardableResult
    func ensureEmbeddingBackend() async -> EmbeddingBackend? {
        if let backend = ragEmbeddingBackend {
            return backend
        }
        guard let backend = selectEmbeddingBackend() else {
            kbLogger.error("No embedding model available; skipping RAG rebuild.")
            return nil
        }
        
        // Initialize components
        let store: SQLiteVectorStore? = await Task.detached {
            return try? SQLiteVectorStore(databaseURL: AppDirs.ragDatabase)
        }.value
        
        ragEmbeddingBackend = backend
        embeddingClient = EmbeddingClientAdapter(backend: backend)
        ragStore = store
        
        if let store = ragStore {
            documentIndexer = DocumentIndexer(embeddingBackend: backend, vectorStore: store)
            if let documentIndexer = documentIndexer {
                codebaseIndexer = CodebaseIndexer(documentIndexer: documentIndexer, documentLibrary: documentLibrary)
            }
        }
        return ragEmbeddingBackend
    }
    
    /// Unload embedding backend to free memory; recreates on demand.
    func unloadEmbeddingBackend() {
        ragEmbeddingBackend = nil
        embeddingClient = nil
        documentIndexer = nil
        codebaseIndexer = nil
    }
    
    /// Returns MLX embedder model IDs available locally (bundled + user models), filtered for MLX format.
    public func embeddingModelsAvailable() -> [String] {
        var names: Set<String> = []
        for folder in ModelStorage.shared.bundledModelFolders() {
            names.insert(folder.lastPathComponent)
        }
        listModelFolders().forEach { names.insert($0) }
        return names
            .filter { id in
                guard let url = findModelURL(for: id) else { return false }
                let format = ModelFormatDetector.detectFormat(at: url)
                return format == .mlx
            }
            .sorted()
    }
    
    /// Recreate the embedding backend with the current selection and rebuild the knowledge base.
    @MainActor
    public func reloadEmbeddingBackend() async {
        unloadEmbeddingBackend()
        _ = await ensureEmbeddingBackend()
        await self.rebuildKnowledgeBase()
    }

    /// Manually load the embedding backend without triggering a rebuild.
    @MainActor
    public func loadEmbeddingBackend() async {
        _ = await ensureEmbeddingBackend()
    }
    
    /// Internal helper to select the embedding backend based on user choice and available MLX models.
    fileprivate func selectEmbeddingBackend() -> (any EmbeddingBackend)? {
        let candidates = embeddingModelsAvailable()
        print("RAG: Available embedding models: \(candidates)")
        
        // Hard preference order (smallest → larger) to avoid VRAM spikes during RAG.
        let preferredOrder = [
            "bge-m3",
            "all-MiniLM-L6-v2-8bit",
            "bge-small-en-v1.5-bf16"
        ]
        
        // Respect user selection if it exists, otherwise pick the first preferred match, else first candidate.
        let ordered: [String] = {
            if let chosen = selectedEmbeddingModelId, !chosen.isEmpty, candidates.contains(chosen) {
                print("RAG: Using user selected model: \(chosen)")
                return [chosen]
            }
            let preferred = preferredOrder.first(where: { candidates.contains($0) })
            if let preferred { 
                print("RAG: Using preferred model: \(preferred)")
                return [preferred] 
            }
            print("RAG: Fallback to first candidate: \(candidates.first ?? "None")")
            return candidates
        }()
        
        if let chosen = ordered.first {
            // Choose smallest-friendly backend by name
            switch chosen {
            case "all-MiniLM-L6-v2-8bit", "bge-small-en-v1.5-bf16":
                return MLXEmbeddingBackend(modelId: chosen)
            default:
                return BGEM3Embedder(modelId: chosen)
            }
        }
        print("RAG: No embedding backend selected")
        return nil
    }
}
#endif
