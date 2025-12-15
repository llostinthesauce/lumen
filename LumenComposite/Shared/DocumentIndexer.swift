import Foundation

/// Handles chunking and embedding for documents into the vector store.
/// We keep chunking logic here so there is a single path from text/code -> embeddings.
public final class DocumentIndexer {
    /// Result summary from indexing operations
    public struct IndexingResult {
        public let indexed: Int
        public let skipped: Int
        public let skipReasons: [String: Int]
        public let chunksCreated: Int
        
        public init(indexed: Int = 0, skipped: Int = 0, skipReasons: [String: Int] = [:], chunksCreated: Int = 0) {
            self.indexed = indexed
            self.skipped = skipped
            self.skipReasons = skipReasons
            self.chunksCreated = chunksCreated
        }
        
        public var summary: String {
            var parts: [String] = []
            parts.append("Indexed: \(indexed) documents")
            if chunksCreated > 0 {
                parts.append("\(chunksCreated) chunks")
            }
            if skipped > 0 {
                parts.append("Skipped: \(skipped)")
                let reasons = skipReasons.map { "\($0.key) (\($0.value))" }.joined(separator: ", ")
                if !reasons.isEmpty {
                    parts.append("[\(reasons)]")
                }
            }
            return parts.joined(separator: " • ")
        }
    }
    
    public enum IndexingError: LocalizedError {
        case fileTooLarge(size: Int, limit: Int)
        case binaryContent
        case emptyContent
        case invalidContent(reason: String)
        
        public var errorDescription: String? {
            switch self {
            case .fileTooLarge(let size, let limit):
                let sizeMB = Double(size) / 1_000_000
                let limitMB = Double(limit) / 1_000_000
                return "File too large (\(String(format: "%.1f", sizeMB))MB, limit: \(String(format: "%.1f", limitMB))MB)"
            case .binaryContent:
                return "Binary content detected"
            case .emptyContent:
                return "Empty or whitespace-only content"
            case .invalidContent(let reason):
                return "Invalid content: \(reason)"
            }
        }
    }
    
    public struct ChunkingConfig {
        let textChunkSize: Int
        let textChunkOverlap: Int
        let codeMaxLines: Int
        let codeLineOverlap: Int
        let maxFileSizeBytes: Int
        
        public init(
            textChunkSize: Int = 1000,
            textChunkOverlap: Int = 200,
            codeMaxLines: Int = 80,
            codeLineOverlap: Int = 10,
            maxFileSizeBytes: Int = 10_000_000  // 10MB default
        ) {
            self.textChunkSize = textChunkSize
            self.textChunkOverlap = textChunkOverlap
            self.codeMaxLines = codeMaxLines
            self.codeLineOverlap = codeLineOverlap
            self.maxFileSizeBytes = maxFileSizeBytes
        }
    }

    private let embeddingBackend: EmbeddingBackend
    private let vectorStore: VectorStore
    private let chunking: ChunkingConfig
    
    public init(
        embeddingBackend: EmbeddingBackend,
        vectorStore: VectorStore,
        chunking: ChunkingConfig = .init()
    ) {
        self.embeddingBackend = embeddingBackend
        self.vectorStore = vectorStore
        self.chunking = chunking
    }
    
    /// Index a document with validation and error handling
    public func indexDocument(
        sourceID: String,
        content: String,
        kind: UserDocumentKind = .generic,
        metadata: [String: Any]? = nil
    ) async throws {
        // Validate content size
        let contentBytes = content.utf8.count
        guard contentBytes <= chunking.maxFileSizeBytes else {
            throw IndexingError.fileTooLarge(size: contentBytes, limit: chunking.maxFileSizeBytes)
        }
        
        // Detect binary content
        guard !isBinaryContent(content) else {
            throw IndexingError.binaryContent
        }
        
        // Check for empty content
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw IndexingError.emptyContent
        }
        
        let chunks = chunk(content: content, kind: kind)
        guard !chunks.isEmpty else { 
            throw IndexingError.emptyContent
        }
        let texts = chunks.map { $0.text }
        
        // Process in batches to avoid overwhelming the embedding backend
        // Batch size of 2 + sleep ensures we don't lock up the GPU/UI
        let batchSize = 2
        var allEmbeddings: [[Float]] = []
        
        for i in stride(from: 0, to: texts.count, by: batchSize) {
            let end = min(i + batchSize, texts.count)
            let batch = Array(texts[i..<end])
            let batchEmbeddings = try await embeddingBackend.embed(texts: batch)
            allEmbeddings.append(contentsOf: batchEmbeddings)
            // Yield to let the system/UI breathe
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        
        var entries: [VectorDocumentChunk] = []
        for (chunk, embedding) in zip(chunks, allEmbeddings) {
            entries.append(
                VectorDocumentChunk(
                    sourceID: sourceID,
                    chunkIndex: chunk.index,
                    content: chunk.text,
                    embedding: embedding,
                    metadata: metadata
                )
            )
        }
        try vectorStore.upsertChunks(entries)
    }
    
    /// Delete document with proper error propagation
    public func deleteDocument(with sourceID: String) throws {
        try vectorStore.deleteChunks(for: sourceID)
    }
    
    /// Reset vector store with proper error propagation
    public func reset() throws {
        try vectorStore.clear()
    }
    
    /// Detect binary content more thoroughly
    private func isBinaryContent(_ content: String) -> Bool {
        // Check for null bytes (classic binary indicator)
        if content.contains("\0") {
            return true
        }
        
        // Check for high ratio of non-printable characters
        let nonPrintableCount = content.unicodeScalars.filter { scalar in
            let value = scalar.value
            // Allow common whitespace but reject other control characters
            return value < 32 && value != 9 && value != 10 && value != 13
        }.count
        
        let threshold = content.count / 100 // 1% threshold
        return nonPrintableCount > threshold
    }
    
    private func chunk(content: String, kind: UserDocumentKind) -> [(index: Int, text: String)] {
        switch kind {
        case .code:
            return chunkCode(content: content)
        default:
            return chunkText(content: content)
        }
    }
    
    private func chunkText(content: String) -> [(index: Int, text: String)] {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        var result: [(Int, String)] = []
        var start = normalized.startIndex
        var index = 0
        
        while start < normalized.endIndex {
            let end = normalized.index(start, offsetBy: chunking.textChunkSize, limitedBy: normalized.endIndex) ?? normalized.endIndex
            let slice = normalized[start..<end]
            let trimmed = slice.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                result.append((index, trimmed))
                index += 1
            }
            if end == normalized.endIndex {
                break
            }
            let overlapDistance = min(chunking.textChunkOverlap, chunking.textChunkSize)
            start = normalized.index(end, offsetBy: -overlapDistance, limitedBy: normalized.startIndex) ?? normalized.startIndex
        }
        return result
    }
    
    private func chunkCode(content: String) -> [(index: Int, text: String)] {
        let lines = content.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
        guard !lines.isEmpty else { return [] }
        var start = 0
        var index = 0
        var chunks: [(Int, String)] = []
        
        while start < lines.count {
            let end = min(start + chunking.codeMaxLines, lines.count)
            let slice = lines[start..<end]
            let joined = slice.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty {
                chunks.append((index, joined))
                index += 1
            }
            if end == lines.count { break }
            let overlapStart = max(0, end - chunking.codeLineOverlap)
            start = overlapStart
        }
        return chunks
    }
}
