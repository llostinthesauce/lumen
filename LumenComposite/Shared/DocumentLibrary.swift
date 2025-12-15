import Foundation
import Combine
#if canImport(PDFKit)
import PDFKit
#endif

public final class DocumentLibrary: ObservableObject {
    @Published public private(set) var documents: [UserDocument] = []
    @Published public private(set) var chunksByDocument: [UUID: [DocumentChunk]] = [:] {
        didSet { rebuildChunkLookup() }
    }
    
    public let vectorIndex = VectorIndex()
    
    private let fileManager = FileManager.default
    private let metadataURL: URL
    private let chunksURL: URL
    private let vectorURL: URL
    private let documentsRoot: URL
    private let embeddingQueue = DispatchQueue(label: "com.lumen.document-library.embedding", qos: .userInitiated)
    private var chunkLookup: [UUID: DocumentChunk] = [:]
    
    public init() {
        let knowledgeRoot = AppDirs.knowledgeBase
        metadataURL = knowledgeRoot.appendingPathComponent("documents.json")
        chunksURL = knowledgeRoot.appendingPathComponent("chunks.json")
        vectorURL = AppDirs.vectorIndex
        documentsRoot = knowledgeRoot.appendingPathComponent("Files", isDirectory: true)
        ensureDirectories()
        loadFromDisk()
    }
    
    // MARK: - Persistence
    
    public func loadFromDisk() {
        documents = (try? loadJSON([UserDocument].self, from: metadataURL)) ?? []
        chunksByDocument = (try? loadJSON([UUID: [DocumentChunk]].self, from: chunksURL)) ?? [:]
        vectorIndex.load(from: vectorURL)
    }
    
    /// Remove all knowledge base artifacts (files, metadata, vectors) and re-create an empty library.
    @MainActor
    public func wipeAll() {
        let fm = FileManager.default
        let root = AppDirs.knowledgeBase
        if fm.fileExists(atPath: root.path) {
            do {
                try fm.removeItem(at: root)
            } catch {
                print("Failed to remove knowledge base: \(error.localizedDescription)")
            }
        }
        documents.removeAll()
        chunksByDocument.removeAll()
        vectorIndex.clear()
        ensureDirectories()
        persist()
    }
    
    public func persist() {
        try? saveJSON(documents, to: metadataURL)
        try? saveJSON(chunksByDocument, to: chunksURL)
        vectorIndex.save(to: vectorURL)
    }
    
    // MARK: - CRUD
    
    @discardableResult
    public func importDocument(from sourceURL: URL, kind: UserDocumentKind = .generic) throws -> UserDocument {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { sourceURL.stopAccessingSecurityScopedResource() }
        }
        
        let content = try extractText(from: sourceURL)
        
        let documentID = UUID()
        var document = UserDocument(
            id: documentID,
            title: sourceURL.deletingPathExtension().lastPathComponent,
            kind: kind,
            fileURL: destinationURL(for: sourceURL.lastPathComponent, documentID: documentID)
        )
        
        document.wordCount = content.split(whereSeparator: \.isWhitespace).count
        document.preview = String(content.prefix(200))
        
        try copyOriginal(sourceURL, to: document.fileURL)
        
        let chunks = chunk(text: content, documentID: documentID)
        documents.append(document)
        chunksByDocument[documentID] = chunks
        persist()
        return document
    }
    
    public func removeDocument(_ documentID: UUID) {
        let doc = documents.first { $0.id == documentID }
        documents.removeAll { $0.id == documentID }
        chunksByDocument.removeValue(forKey: documentID)
        vectorIndex.removeEntries(for: documentID)
        if let doc {
            deleteOriginal(for: doc)
        }
        persist()
    }
    
    public func textContent(for document: UserDocument) -> String? {
        do {
            return try extractText(from: document.fileURL)
        } catch {
            return nil
        }
    }
    
    // MARK: - Embeddings
    
    public func updateEmbeddings(for documentID: UUID, vectors: [[Float]]) {
        guard let chunks = chunksByDocument[documentID], vectors.count == chunks.count else { return }
        let entries: [EmbeddedChunk] = zip(chunks, vectors).map { chunk, vector in
            EmbeddedChunk(chunkID: chunk.id, documentID: chunk.documentID, index: chunk.index, vector: vector)
        }
        vectorIndex.replaceEntries(for: documentID, with: entries)
        vectorIndex.save(to: vectorURL)
    }
    
    public func rebuildIndex(includeCode: Bool = false, embeddingClient: EmbeddingClient) async throws {
        let allChunks = buildChunks(includeCode: includeCode)
        guard !allChunks.isEmpty else {
            await MainActor.run {
                self.chunksByDocument = [:]
                self.vectorIndex.clear()
                self.persist()
            }
            return
        }
        
        // Embed in small batches to avoid GPU over-allocation
        let batchSize = 2
        var embedded: [EmbeddedChunk] = []
        for start in stride(from: 0, to: allChunks.count, by: batchSize) {
            let end = min(start + batchSize, allChunks.count)
            let batch = Array(allChunks[start..<end])
            let vectors = try await embedTexts(batch.map { $0.text }, using: embeddingClient)
            guard vectors.count == batch.count else {
                throw NSError(domain: "DocumentLibrary", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "Embedding count mismatch"
                ])
            }
            for (chunk, vector) in zip(batch, vectors) {
                embedded.append(
                    EmbeddedChunk(
                        chunkID: chunk.id,
                        documentID: chunk.documentID,
                        index: chunk.index,
                        vector: vector.map { Float($0) }
                    )
                )
            }
            // brief pause to yield
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        
        await MainActor.run {
            self.chunksByDocument = Dictionary(grouping: allChunks, by: { $0.documentID })
            self.vectorIndex.clear()
            self.vectorIndex.addEntries(embedded)
            self.persist()
        }
    }
    
    public func querySimilarChunks(for vector: [Float], topK: Int) -> [DocumentChunk] {
        let hits = vectorIndex.query(vector: vector, topK: topK)
        return hits.compactMap { chunkLookup[$0.chunkID] }
    }
    
    // MARK: - Helpers
    
    private func ensureDirectories() {
        try? fileManager.createDirectory(at: documentsRoot, withIntermediateDirectories: true, attributes: nil)
        let vectorDir = vectorURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: vectorDir, withIntermediateDirectories: true, attributes: nil)
    }
    
    private func destinationURL(for filename: String, documentID: UUID) -> URL {
        let folder = documentsRoot.appendingPathComponent(documentID.uuidString, isDirectory: true)
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: nil)
        return folder.appendingPathComponent(filename)
    }
    
    private func copyOriginal(_ source: URL, to destination: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            try? fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }
    
    private func deleteOriginal(for document: UserDocument) {
        let folder = document.fileURL.deletingLastPathComponent()
        try? fileManager.removeItem(at: folder)
    }
    
    @discardableResult
    public func registerCodeDocument(fileURL: URL, title: String, workspaceID: UUID) -> UserDocument {
        var document: UserDocument
        if let existingIndex = documents.firstIndex(where: { $0.fileURL == fileURL }) {
            document = documents[existingIndex]
            document.title = title
            document.kind = .code
            document.workspaceID = workspaceID
            document.updatedAt = Date()
            documents[existingIndex] = document
        } else {
            document = UserDocument(
                title: title,
                kind: .code,
                fileURL: fileURL,
                workspaceID: workspaceID
            )
            documents.append(document)
        }
        persist()
        return document
    }
    
    public func purgeCodeDocuments(for workspaceID: UUID) {
        let removedIDs = documents.filter { $0.workspaceID == workspaceID }.map { $0.id }
        documents.removeAll { $0.workspaceID == workspaceID }
        removedIDs.forEach { chunksByDocument.removeValue(forKey: $0) }
        persist()
    }

    public func document(forFileURL url: URL) -> UserDocument? {
        documents.first { $0.fileURL == url }
    }
    
    private func chunk(text: String, documentID: UUID, chunkSize: Int = 400, overlap: Int = 100) -> [DocumentChunk] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var start = normalized.startIndex
        var chunks: [DocumentChunk] = []
        var chunkIndex = 0
        
        while start < normalized.endIndex {
            let end = normalized.index(start, offsetBy: chunkSize, limitedBy: normalized.endIndex) ?? normalized.endIndex
            let slice = normalized[start..<end]
            let chunkText = slice.trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunkText.isEmpty {
                chunks.append(DocumentChunk(documentID: documentID, index: chunkIndex, text: chunkText))
                chunkIndex += 1
            }
            if end == normalized.endIndex { break }
            let overlapOffset = min(overlap, chunkSize)
            guard let newStart = normalized.index(end, offsetBy: -overlapOffset, limitedBy: normalized.startIndex) else {
                break
            }
            start = newStart
        }
        
        return chunks
    }
    
    private func chunkCode(text: String, documentID: UUID, maxLines: Int = 60, overlapLines: Int = 8) -> [DocumentChunk] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard !lines.isEmpty else { return [] }
        var start = 0
        var index = 0
        var chunks: [DocumentChunk] = []
        
        while start < lines.count {
            let end = min(start + maxLines, lines.count)
            let slice = lines[start..<end]
            let joined = slice.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty {
                chunks.append(DocumentChunk(documentID: documentID, index: index, text: joined))
                index += 1
            }
            if end == lines.count { break }
            let overlapStart = max(0, end - overlapLines)
            start = overlapStart
        }
        return chunks
    }
    
    private func buildChunks(includeCode: Bool) -> [DocumentChunk] {
        var result: [DocumentChunk] = []
        for doc in documents {
            if doc.kind == .code && !includeCode { continue }
            if isTooLargeForEmbedding(doc.fileURL) {
                print("Skipping embedding for large file: \(doc.title)")
                continue
            }
            guard let text = loadText(at: doc.fileURL) else { continue }
            let chunks = (doc.kind == .code) ? chunkCode(text: text, documentID: doc.id) : chunk(text: text, documentID: doc.id)
            result.append(contentsOf: chunks)
        }
        return result
    }
    
    private func loadText(at url: URL) -> String? {
        return try? extractText(from: url)
    }
    
    private func rebuildChunkLookup() {
        var map: [UUID: DocumentChunk] = [:]
        for (_, chunks) in chunksByDocument {
            for chunk in chunks {
                map[chunk.id] = chunk
            }
        }
        chunkLookup = map
    }
    
    private func loadJSON<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }
    
    private func saveJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try JSONEncoder().encode(value)
        try data.write(to: url, options: [.atomic])
    }
    
    private func isTooLargeForEmbedding(_ url: URL, maxBytes: Int64 = 1_500_000) -> Bool {
        if let attrs = try? fileManager.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? NSNumber {
            return size.int64Value > maxBytes
        }
        return false
    }

    private func embedTexts(_ texts: [String], using client: EmbeddingClient) async throws -> [[Double]] {
        try await client.embed(texts: texts)
    }

    private func extractText(from url: URL) throws -> String {
        if let text = (try? String(contentsOf: url, encoding: .utf8)) ??
            (try? String(contentsOf: url, encoding: .utf16)) ??
            (try? String(contentsOf: url, encoding: .unicode)) {
            let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalized.isEmpty {
                return text
            }
        }
        
#if canImport(PDFKit)
        if url.pathExtension.lowercased() == "pdf",
           let pdfDocument = PDFDocument(url: url) {
            var combined = ""
            for index in 0..<pdfDocument.pageCount {
                if let page = pdfDocument.page(at: index),
                   let text = page.string {
                    combined += text
                    combined += "\n"
                }
            }
            let normalized = combined.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalized.isEmpty {
                return combined
            }
        }
#endif
        
#if os(macOS) || os(iOS)
        if let richText = try? NSAttributedString(url: url, options: [:], documentAttributes: nil) {
            let normalized = richText.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalized.isEmpty {
                return richText.string
            }
        }
#endif
        
        if let data = try? Data(contentsOf: url) {
            if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                return text
            }
            if let text = String(data: data, encoding: .utf16)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                return text
            }
        }
        
        throw NSError(domain: "DocumentLibrary", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Unable to read text contents for \(url.lastPathComponent)"
        ])
    }
}
