import Foundation
import Combine
import os

extension AppState {
    // MARK: - Document Library
    
    @discardableResult
    public func importUserDocument(from url: URL, kind: UserDocumentKind = .generic) throws -> UserDocument {
        try documentLibrary.importDocument(from: url, kind: kind)
    }
    
    public func importUserDocuments(from urls: [URL], kind: UserDocumentKind = .generic) -> [UserDocument] {
        var imported: [UserDocument] = []
        for url in urls {
            if let doc = try? documentLibrary.importDocument(from: url, kind: kind) {
                imported.append(doc)
                if autoIndexingEnabled {
                    Task {
                        await self.indexDocumentForRAG(doc)
                    }
                }
            }
        }
        return imported
    }
    
    public func removeUserDocument(_ documentID: UUID) {
        documentLibrary.removeDocument(documentID)
        try? documentIndexer?.deleteDocument(with: documentID.uuidString)
        try? ragStore?.deleteChunks(for: documentID.uuidString)
        scheduleKnowledgeSnapshotPersistence()
    }
    
    public func updateDocumentEmbeddings(documentID: UUID, vectors: [[Float]]) {
        documentLibrary.updateEmbeddings(for: documentID, vectors: vectors)
    }
    
    public func queryUserDocuments(vector: [Float], topK: Int = 5) -> [DocumentChunk] {
        documentLibrary.querySimilarChunks(for: vector, topK: topK)
    }
    
    // MARK: - Knowledge Base
    
    public func rebuildKnowledgeBase(includeCode: Bool = false) async {
        guard !isKnowledgeIndexing else {
            kbLogger.log("Knowledge rebuild already in progress; skipping duplicate request.")
            return
        }
        guard let backend = await ensureEmbeddingBackend() else { return }
        guard let client = embeddingClient else { return }
        guard !documents.isEmpty else {
            kbLogger.log("No documents to index; skipping knowledge rebuild.")
            return
        }
        // Free VRAM pressure from the chat model before indexing; user can reload after.
        Task {
            await unloadCurrentModel()
        }
        beginKnowledgeIndexing()
        let library = documentLibrary
        let allDocuments = documents
        let ragStore = self.ragStore
        let indexer = documentIndexer
        Task.detached(priority: .utility) { [weak self] in
            do {
                indexer?.reset()
                try ragStore?.clear()
                if let indexer = indexer {
                    for document in allDocuments {
                        guard let content = try? String(contentsOf: document.fileURL) else { continue }
                        let metadata: [String: Any] = [
                            "title": document.title,
                            "kind": document.kind.rawValue,
                            "documentID": document.id.uuidString
                        ]
                        try await indexer.indexDocument(
                            sourceID: document.id.uuidString,
                            content: content,
                            kind: document.kind,
                            metadata: metadata
                        )
                    }
                }
                await MainActor.run {
                    self?.persistKnowledgeSnapshot(for: allDocuments)
                    self?.endKnowledgeIndexing()
                }
            } catch {
                await MainActor.run {
                    self?.kbLogger.error("DocumentLibrary rebuild failed: \(error.localizedDescription, privacy: .public)")
                    print("Failed to rebuild knowledge base: \(error)")
                    self?.endKnowledgeIndexing()
                }
            }
        }
        // Unload embedder after manual rebuild to free memory
        unloadEmbeddingBackend()
    }
    
    public func relevantDocumentChunks(
        for question: String,
        topK: Int = 10,
        workspaceFilter: Set<UUID>? = nil
    ) async -> [DocumentChunk] {
        // Do not auto-load the embedder when it's not already present; avoid unexpected memory use.
        guard let client = embeddingClient, let store = ragStore else { return [] }
        do {
            let vectors = try await embedQueryTexts([question], using: client)
            guard let raw = vectors.first else { return [] }
            let hits = try store.searchSimilar(for: raw.map { Float($0) }, topK: topK)
            print("RAG: Vector search found \(hits.count) hits")
            logRAGHits(question: question, retrieved: hits)
            return hits.compactMap { chunk in
                let docIDString = chunk.metadata?["documentID"] as? String
                let docID = docIDString.flatMap(UUID.init(uuidString:)) ?? UUID()
                guard documentPassesWorkspaceFilter(documentID: docID, workspaceFilter: workspaceFilter) else {
                    return nil
                }
                return DocumentChunk(
                    documentID: docID,
                    index: chunk.chunkIndex,
                    text: chunk.content
                )
            }
        } catch {
            print("Vector search failed \(error)")
            return []
        }
    }
    
    public func debugGetAllChunks() -> [VectorDocumentChunk] {
        guard let store = ragStore else { return [] }
        return (try? store.getAllChunks()) ?? []
    }
    
    /// Fully remove all knowledge base data, including documents, embeddings, workspaces, and metadata.
    public func wipeKnowledgeBase() {
#if os(iOS)
        kbLogger.log("Knowledge base wipe ignored on iOS (no KB features enabled)")
        return
#endif
        Task { [weak self] in
            guard let self else { return }
            kbLogger.log("Knowledge base wipe requested")
            await MainActor.run {
                self.isKnowledgeIndexing = false
            }
            // Release embedding resources and close stores before deleting files
            unloadEmbeddingBackend()
            ragStore = nil
            
#if os(macOS)
            await MainActor.run {
                stopBlackHoleWatcher()
                blackHoleFolderURL = nil
                blackHoleEnabled = false
                blackHoleRegistry.removeAll()
                UserDefaults.standard.removeObject(forKey: Self.blackHoleBookmarkKey)
                UserDefaults.standard.removeObject(forKey: Self.blackHoleRegistryKey)
            }
            await MainActor.run {
                for workspace in codeWorkspaces {
                    stopWatching(workspace)
                }
                codeWorkspaces.removeAll()
                saveCodeWorkspaces()
            }
            workspaceAccessRevokers.values.forEach { $0() }
            workspaceAccessRevokers.removeAll()
            watchers.removeAll()
#endif
            
            // Remove on-disk artifacts and reset in-memory views
            await documentLibrary.wipeAll()
            await MainActor.run {
                self.documents = self.documentLibrary.documents
                self.documentChunks = self.documentLibrary.chunksByDocument
                self.lastKnowledgeSnapshot = nil
                self.knowledgeIndexBuilt = false
                self.knowledgeIndexingCount = 0
                UserDefaults.standard.removeObject(forKey: Self.knowledgeSnapshotKey)
                UserDefaults.standard.removeObject(forKey: Self.knowledgeSnapshotBuiltKey)
            }
            
            // Clean ancillary files that live alongside the knowledge base
            let fm = FileManager.default
            try? fm.removeItem(at: AppDirs.ragDatabase)
            try? fm.removeItem(at: AppDirs.modelDefaults)
            try? fm.removeItem(at: AppDirs.workspaceMetadata)
            
            // Recreate an empty vector store for future indexing
            ragStore = try? SQLiteVectorStore(databaseURL: AppDirs.ragDatabase)

#if os(macOS)
            // Recreate the BlackHole folder under KnowledgeBase so future use has the expected path.
            _ = AppDirs.blackHole
#endif
        }
    }
    
    public func purgeVectorDatabase() {
        Task {
            do {
                try ragStore?.clear()
                try? documentIndexer?.reset()
                await MainActor.run {
                    self.kbLogger.log("Vector database purged by user")
                    // Also clear the knowledge snapshot so it rebuilds if needed later
                    self.lastKnowledgeSnapshot = nil
                    self.knowledgeIndexBuilt = false
                    UserDefaults.standard.removeObject(forKey: Self.knowledgeSnapshotKey)
                    UserDefaults.standard.removeObject(forKey: Self.knowledgeSnapshotBuiltKey)
                }
            } catch {
                print("Failed to purge vector database: \(error)")
            }
        }
    }
    
    // MARK: - Internal helpers
    
    private func embedQueryTexts(_ texts: [String], using client: EmbeddingClient) async throws -> [[Double]] {
        try await client.embed(texts: texts)
    }
    
    private func beginKnowledgeIndexing() {
        knowledgeIndexingCount += 1
        isKnowledgeIndexing = true
        kbLogger.log("Knowledge indexing started (count=\(self.knowledgeIndexingCount))")
    }
    
    private func endKnowledgeIndexing() {
        knowledgeIndexingCount = max(0, knowledgeIndexingCount - 1)
        if knowledgeIndexingCount == 0 {
            isKnowledgeIndexing = false
        }
        kbLogger.log("Knowledge indexing finished (count=\(self.knowledgeIndexingCount))")
    }
    
    private func documentPassesWorkspaceFilter(
        documentID: UUID,
        workspaceFilter: Set<UUID>?
    ) -> Bool {
        guard let filter = workspaceFilter, let doc = document(for: documentID) else { return true }
        guard doc.kind == .code else { return true }
        guard let workspaceID = doc.workspaceID else { return false }
        return filter.contains(workspaceID)
    }
    
    private func reindexExistingDocumentsIfNeeded(trackProgress: Bool = true) async {
        guard documentIndexer != nil else { return }
        let docs = documents
        let snapshot = knowledgeSnapshot(for: docs)
        if knowledgeIndexBuilt, let last = lastKnowledgeSnapshot, last == snapshot {
            kbLogger.log("Skipping knowledge reindex (snapshot unchanged)")
            return
        }
        // Auto indexing disabled
        if !autoIndexingEnabled { return }
        if trackProgress { beginKnowledgeIndexing() }
        defer { if trackProgress { endKnowledgeIndexing() } }
        kbLogger.log("Reindexing existing documents (\(docs.count) items)")
        for doc in docs {
            await indexDocumentForRAG(doc, trackProgress: false)
        }
        await MainActor.run {
            self.persistKnowledgeSnapshot(for: docs)
        }
    }
    
    func indexDocumentForRAG(_ document: UserDocument, trackProgress: Bool = true) async {
        let createdBackend = documentIndexer == nil
        if createdBackend {
            print("RAG: Document indexer is nil, attempting to load backend...")
            _ = await ensureEmbeddingBackend()
        }
        guard let indexer = documentIndexer else { 
            print("RAG: Failed to initialize document indexer. Aborting index for \(document.title)")
            return 
        }
        if trackProgress { beginKnowledgeIndexing() }
        let library = documentLibrary
        let doc = document
        let indexingTask = Task.detached(priority: .utility) { () throws -> Bool in
            guard let content = library.textContent(for: doc) else { return false }
            let metadata: [String: Any] = [
                "title": doc.title,
                "kind": doc.kind.rawValue,
                "documentID": doc.id.uuidString
            ]
            try await indexer.indexDocument(
                sourceID: doc.id.uuidString,
                content: content,
                kind: doc.kind,
                metadata: metadata
            )
            return true
        }
        do {
            let didIndex = try await indexingTask.value
            if didIndex {
                kbLogger.log("Indexed document \(document.title, privacy: .public)")
                await MainActor.run {
                    self.persistCurrentKnowledgeSnapshot()
                }
            }
        } catch {
            kbLogger.error("RAG index failed for \(document.title, privacy: .public): \(error.localizedDescription, privacy: .public)")
            print("RAG index failed: \(error)")
        }
        if trackProgress { endKnowledgeIndexing() }
        if createdBackend {
            unloadEmbeddingBackend()
        }
    }
    
    func bindDocumentLibrary() {
        documentLibrary.$documents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] docs in
                self?.documents = docs
            }
            .store(in: &cancellables)
        
        documentLibrary.$chunksByDocument
            .receive(on: DispatchQueue.main)
            .sink { [weak self] chunks in
                self?.documentChunks = chunks
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Knowledge Snapshot Persistence (Cross-platform)
    
    private func knowledgeSnapshot(for docs: [UserDocument]) -> String {
        let entries = docs.map { ($0.id.uuidString, $0.updatedAt.timeIntervalSince1970) }
            .sorted { $0.0 < $1.0 }
        return entries.map { "\($0.0):\($0.1)" }.joined(separator: "|")
    }
    
    @MainActor
    private func persistKnowledgeSnapshot(for docs: [UserDocument]) {
        let snapshot = knowledgeSnapshot(for: docs)
        persistKnowledgeSnapshotValue(snapshot)
    }
    
    @MainActor
    func persistCurrentKnowledgeSnapshot() {
        let snapshot = knowledgeSnapshot(for: documents)
        persistKnowledgeSnapshotValue(snapshot)
    }
    
    private func persistKnowledgeSnapshotValue(_ snapshot: String) {
        lastKnowledgeSnapshot = snapshot
        knowledgeIndexBuilt = true
        UserDefaults.standard.set(snapshot, forKey: Self.knowledgeSnapshotKey)
        UserDefaults.standard.set(true, forKey: Self.knowledgeSnapshotBuiltKey)
    }
    
    private func scheduleKnowledgeSnapshotPersistence() {
        Task { @MainActor in
            self.persistCurrentKnowledgeSnapshot()
        }
    }
}
