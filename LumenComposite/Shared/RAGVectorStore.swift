import Foundation
import SQLite3
import Accelerate
#if canImport(MLX)
import MLX
#endif

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public struct VectorDocumentChunk {
    public let sourceID: String
    public let chunkIndex: Int
    public let content: String
    public let embedding: [Float]
    public let metadata: [String: Any]?
}

public struct RetrievedChunk {
    public let sourceID: String
    public let chunkIndex: Int
    public let content: String
    public let metadata: [String: Any]?
    public let score: Float
}

public protocol VectorStore {
    func upsertChunks(_ chunks: [VectorDocumentChunk]) throws
    func searchSimilar(for queryEmbedding: [Float], topK: Int) throws -> [RetrievedChunk]
    func deleteChunks(for sourceID: String) throws
    func clear() throws
    func getAllChunks() throws -> [VectorDocumentChunk]
    func checkIntegrity() throws -> VectorStoreHealth
}

public struct VectorStoreHealth {
    public let isHealthy: Bool
    public let documentCount: Int
    public let embeddingDimension: Int?
    public let issues: [String]
    
    public var summary: String {
        if isHealthy {
            return "Vector store healthy: \(documentCount) chunks, dimension \(embeddingDimension ?? 0)"
        } else {
            return "Issues found: \(issues.joined(separator: ", "))"
        }
    }
}

public enum VectorStoreError: LocalizedError {
    case dimensionMismatch(expected: Int, got: Int)
    case corruptedDatabase(reason: String)
    case incompatibleEmbedding
    
    public var errorDescription: String? {
        switch self {
        case .dimensionMismatch(let expected, let got):
            return "Embedding dimension mismatch: expected \(expected)D but got \(got)D. Clear the vector store before using a different embedding model."
        case .corruptedDatabase(let reason):
            return "Vector store database is corrupted: \(reason)"
        case .incompatibleEmbedding:
            return "Incompatible embedding format"
        }
    }
}

public final class SQLiteVectorStore: VectorStore {
    private let dbURL: URL
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.lumen.vectorstore")
#if canImport(MLX)
    private struct MLXCache {
        struct Row {
            let sourceID: String
            let chunkIndex: Int
            let content: String
            let metadata: [String: Any]?
        }
        let normalizedEmbeddings: MLXArray
        let rows: [Row]
        let dimension: Int
    }

#if canImport(MLX)
    private func searchWithMLXLocked(queryEmbedding: [Float], topK: Int) throws -> [RetrievedChunk]? {
        guard !queryEmbedding.isEmpty else { return [] }
        guard let cache = try buildMLXCacheLocked() else { return nil }
        guard queryEmbedding.count == cache.dimension else { return nil }
        
        let query = MLXArray(queryEmbedding, [cache.dimension])
        let queryNorm = (query * query).sum().sqrt()
        let normalizedQuery = query / (queryNorm + MLXArray([Float(1e-6)]))
        let scores = cache.normalizedEmbeddings
            .matmul(normalizedQuery.reshaped([cache.dimension, 1]))
            .squeezed()
        
        let flattened = scores.asArray(Float.self)
        guard flattened.count == cache.rows.count else { return nil }
        
        let ranked = zip(cache.rows.indices, flattened)
            .sorted(by: { $0.1 > $1.1 })
            .prefix(topK)
        
        return ranked.map { index, score in
            let row = cache.rows[index]
            return RetrievedChunk(
                sourceID: row.sourceID,
                chunkIndex: row.chunkIndex,
                content: row.content,
                metadata: row.metadata,
                score: score
            )
        }
    }
    
    private func buildMLXCacheLocked() throws -> MLXCache? {
        if let cache = mlxCache { return cache }
        let chunks = try fetchAllChunksLocked()
        guard !chunks.isEmpty else { return nil }
        
        let dimension = chunks.first?.embedding.count ?? 0
        guard dimension > 0 else { return nil }
        let filtered = chunks.filter { $0.embedding.count == dimension }
        guard !filtered.isEmpty else { return nil }
        
        let flattened: [Float] = filtered.flatMap { $0.embedding }
        let matrix = MLXArray(flattened, [filtered.count, dimension])
        let norms = (matrix * matrix).sum(axis: 1, keepDims: true).sqrt()
        let epsilon = MLXArray([Float(1e-6)], [1, 1])
        let normalized = matrix / (norms + epsilon)
        let rows: [MLXCache.Row] = filtered.map { chunk in
            MLXCache.Row(
                sourceID: chunk.sourceID,
                chunkIndex: chunk.chunkIndex,
                content: chunk.content,
                metadata: chunk.metadata
            )
        }
        let cache = MLXCache(
            normalizedEmbeddings: normalized,
            rows: rows,
            dimension: dimension
        )
        mlxCache = cache
        return cache
    }
#endif
    private var mlxCache: MLXCache?
#endif
    
    public init(databaseURL: URL) throws {
        self.dbURL = databaseURL
        try open()
        try createSchema()
    }

    private func invalidateCache() {
#if canImport(MLX)
        mlxCache = nil
#endif
    }
    
    deinit {
        sqlite3_close(db)
    }
    
    private func open() throws {
        let path = dbURL.path
        let result = sqlite3_open(path, &db)
        guard result == SQLITE_OK else {
            throw NSError(domain: "VectorStore", code: Int(result), userInfo: [
                NSLocalizedDescriptionKey: "Failed to open vector store database"
            ])
        }
    }
    
    private func createSchema() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS documents (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            source_id TEXT NOT NULL,
            chunk_index INTEGER NOT NULL,
            content TEXT NOT NULL,
            embedding BLOB NOT NULL,
            metadata TEXT,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_documents_source
        ON documents (source_id, chunk_index);
        
        CREATE TABLE IF NOT EXISTS vector_metadata (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        """
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            throw lastError()
        }
    }
    
    /// Get stored embedding dimension from metadata
    private func getStoredDimension() throws -> Int? {
        let sql = "SELECT value FROM vector_metadata WHERE key = 'embedding_dimension'"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError()
        }
        defer { sqlite3_finalize(statement) }
        
        if sqlite3_step(statement) == SQLITE_ROW,
           let value = sqlite3_column_text(statement, 0) {
            return Int(String(cString: value))
        }
        return nil
    }
    
    /// Store embedding dimension in metadata
    private func storeDimension(_ dimension: Int) throws {
        let sql = "INSERT OR REPLACE INTO vector_metadata (key, value) VALUES ('embedding_dimension', ?)"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError()
        }
        defer { sqlite3_finalize(statement) }
        
        let value = String(dimension)
        sqlite3_bind_text(statement, 1, value, -1, SQLITE_TRANSIENT)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastError()
        }
    }
    
    public func upsertChunks(_ chunks: [VectorDocumentChunk]) throws {
        guard !chunks.isEmpty else { return }
        
        // Validate dimension consistency
        let dimension = chunks.first?.embedding.count ?? 0
        guard dimension > 0 else {
            throw VectorStoreError.incompatibleEmbedding
        }
        
        // Check all chunks have same dimension
        for chunk in chunks {
            guard chunk.embedding.count == dimension else {
                throw VectorStoreError.dimensionMismatch(expected: dimension, got: chunk.embedding.count)
            }
        }
        
        try queue.sync {
            // Check against stored dimension
            if let storedDim = try getStoredDimension() {
                guard storedDim == dimension else {
                    throw VectorStoreError.dimensionMismatch(expected: storedDim, got: dimension)
                }
            } else {
                // First insert, store the dimension
                try storeDimension(dimension)
            }
            
            try beginTransaction()
            defer { sqlite3_exec(db, "COMMIT", nil, nil, nil) }
            
            let deleteSQL = "DELETE FROM documents WHERE source_id = ?"
            let insertSQL = """
            INSERT INTO documents (source_id, chunk_index, content, embedding, metadata, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """
            
            var seenSources: Set<String> = []
            for chunk in chunks {
                if !seenSources.contains(chunk.sourceID) {
                    try delete(sourceID: chunk.sourceID, sql: deleteSQL)
                    seenSources.insert(chunk.sourceID)
                }
                try insert(chunk: chunk, sql: insertSQL)
            }
            invalidateCache()
        }
    }
    
    public func searchSimilar(for queryEmbedding: [Float], topK: Int) throws -> [RetrievedChunk] {
        guard topK > 0 else { return [] }
        return try queue.sync {
#if canImport(MLX)
            if let accelerated = try searchWithMLXLocked(queryEmbedding: queryEmbedding, topK: topK) {
                return accelerated
            }
#endif
            return try searchWithSQLLocked(queryEmbedding: queryEmbedding, topK: topK)
        }
    }
    
    public func getAllChunks() throws -> [VectorDocumentChunk] {
        try queue.sync { try fetchAllChunksLocked() }
    }
    
    public func deleteChunks(for sourceID: String) throws {
        try queue.sync {
            try beginTransaction()
            defer { sqlite3_exec(db, "COMMIT", nil, nil, nil) }
            try delete(sourceID: sourceID, sql: "DELETE FROM documents WHERE source_id = ?")
            invalidateCache()
        }
    }
    
    public func clear() throws {
        try queue.sync {
            if sqlite3_exec(db, "DELETE FROM documents", nil, nil, nil) != SQLITE_OK {
                throw lastError()
            }
            // Also clear dimension metadata when clearing all documents
            if sqlite3_exec(db, "DELETE FROM vector_metadata WHERE key = 'embedding_dimension'", nil, nil, nil) != SQLITE_OK {
                throw lastError()
            }
            invalidateCache()
        }
    }
    
    public func checkIntegrity() throws -> VectorStoreHealth {
        return try queue.sync {
            var issues: [String] = []
            var dimension: Int? = nil
            
            // Check if tables exist
            let tableCheck = "SELECT name FROM sqlite_master WHERE type='table' AND name='documents'"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, tableCheck, -1, &stmt, nil) == SQLITE_OK else {
                throw lastError()
            }
            defer { sqlite3_finalize(stmt) }
            
            guard sqlite3_step(stmt) == SQLITE_ROW else {
                issues.append("Documents table missing")
                return VectorStoreHealth(isHealthy: false, documentCount: 0, embeddingDimension: nil, issues: issues)
            }
            
            // Get document count
            let countSQL = "SELECT COUNT(*) FROM documents"
            var countStmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, countSQL, -1, &countStmt, nil) == SQLITE_OK else {
                throw lastError()
            }
            defer { sqlite3_finalize(countStmt) }
            
            var documentCount = 0
            if sqlite3_step(countStmt) == SQLITE_ROW {
                documentCount = Int(sqlite3_column_int(countStmt, 0))
            }
            
            // Get stored dimension
            dimension = try? getStoredDimension()
            
            // Verify embedding dimensions are consistent
            if documentCount > 0 {
                let chunks = try fetchAllChunksLocked()
                if let firstDim = chunks.first?.embedding.count {
                    for chunk in chunks {
                        if chunk.embedding.count != firstDim {
                            issues.append("Inconsistent embedding dimensions found")
                            break
                        }
                    }
                    
                    if let storedDim = dimension, storedDim != firstDim {
                        issues.append("Stored dimension (\(storedDim)) doesn't match actual (\(firstDim))")
                    }
                }
            }
            
            let isHealthy = issues.isEmpty
            return VectorStoreHealth(
                isHealthy: isHealthy,
                documentCount: documentCount,
                embeddingDimension: dimension,
                issues: issues
            )
        }
    }

    private func searchWithSQLLocked(queryEmbedding: [Float], topK: Int) throws -> [RetrievedChunk] {
        guard !queryEmbedding.isEmpty else { return [] }
        let chunks = try fetchAllChunksLocked()
        guard !chunks.isEmpty else { return [] }
        
        var results: [RetrievedChunk] = []
        for chunk in chunks {
            guard chunk.embedding.count == queryEmbedding.count else { continue }
            let score = cosineSimilarity(queryEmbedding, chunk.embedding)
            results.append(
                RetrievedChunk(
                    sourceID: chunk.sourceID,
                    chunkIndex: chunk.chunkIndex,
                    content: chunk.content,
                    metadata: chunk.metadata,
                    score: score
                )
            )
        }
        return results
            .sorted(by: { $0.score > $1.score })
            .prefix(topK)
            .map { $0 }
    }
    
    private func fetchAllChunksLocked() throws -> [VectorDocumentChunk] {
        let sql = "SELECT source_id, chunk_index, content, embedding, metadata FROM documents"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError()
        }
        defer { sqlite3_finalize(statement) }
        
        var results: [VectorDocumentChunk] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let source = sqlite3_column_text(statement, 0),
                let contentPointer = sqlite3_column_text(statement, 2),
                let blob = sqlite3_column_blob(statement, 3)
            else { continue }
            
            let sourceID = String(cString: source)
            let chunkIndex = Int(sqlite3_column_int(statement, 1))
            let content = String(cString: contentPointer)
            let blobSize = Int(sqlite3_column_bytes(statement, 3))
            let floatCount = blobSize / MemoryLayout<Float>.size
            
            var embedding = [Float](repeating: 0, count: floatCount)
            memcpy(&embedding, blob, blobSize)
            
            var metadataDict: [String: Any]? = nil
            if let metadataText = sqlite3_column_text(statement, 4) {
                let metadataString = String(cString: metadataText)
                if let data = metadataString.data(using: .utf8) {
                    metadataDict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                }
            }
            
            results.append(
                VectorDocumentChunk(
                    sourceID: sourceID,
                    chunkIndex: chunkIndex,
                    content: content,
                    embedding: embedding,
                    metadata: metadataDict
                )
            )
        }
        return results
    }
    
    private func delete(sourceID: String, sql: String) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError()
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, sourceID, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastError()
        }
    }
    
    private func insert(chunk: VectorDocumentChunk, sql: String) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError()
        }
        defer { sqlite3_finalize(statement) }
        
        sqlite3_bind_text(statement, 1, chunk.sourceID, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 2, Int32(chunk.chunkIndex))
        sqlite3_bind_text(statement, 3, chunk.content, -1, SQLITE_TRANSIENT)
        let data = Data(buffer: UnsafeBufferPointer(start: chunk.embedding, count: chunk.embedding.count))
        data.withUnsafeBytes { ptr in
            sqlite3_bind_blob(statement, 4, ptr.baseAddress, Int32(ptr.count), SQLITE_TRANSIENT)
        }
        if let metadata = chunk.metadata,
           let json = try? JSONSerialization.data(withJSONObject: metadata),
           let jsonString = String(data: json, encoding: .utf8) {
            sqlite3_bind_text(statement, 5, jsonString, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, 5)
        }
        let timestamp = Date().timeIntervalSince1970
        sqlite3_bind_double(statement, 6, timestamp)
        sqlite3_bind_double(statement, 7, timestamp)
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastError()
        }
    }
    
    private func beginTransaction() throws {
        if sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil) != SQLITE_OK {
            throw lastError()
        }
    }
    
    private func lastError() -> NSError {
        let message = String(cString: sqlite3_errmsg(db))
        return NSError(domain: "VectorStore", code: 1, userInfo: [
            NSLocalizedDescriptionKey: message
        ])
    }
    
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        var magA: Float = 0
        var magB: Float = 0
        vDSP_svesq(a, 1, &magA, vDSP_Length(a.count))
        vDSP_svesq(b, 1, &magB, vDSP_Length(b.count))
        let denom = sqrt(magA) * sqrt(magB)
        return denom > 0 ? dot / denom : 0
    }
}
