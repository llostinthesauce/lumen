import Foundation

public struct RAGConfig {
    public let topK: Int
    public let systemPrompt: String
    public let includeScores: Bool
    
    public init(
        topK: Int = 6,
        systemPrompt: String = "You are a helpful assistant. Answer the question based on the provided context. If the context doesn't contain enough information, say so.",
        includeScores: Bool = false
    ) {
        self.topK = topK
        self.systemPrompt = systemPrompt
        self.includeScores = includeScores
    }
}

public final class RAGOrchestrator {
    private let embeddingBackend: EmbeddingBackend
    private let vectorStore: VectorStore
    private let llm: ChatEngine
    
    public init(
        embeddingBackend: EmbeddingBackend,
        vectorStore: VectorStore,
        llm: ChatEngine
    ) {
        self.embeddingBackend = embeddingBackend
        self.vectorStore = vectorStore
        self.llm = llm
    }
    
    /// Answer a query using RAG
    public func answer(query: String, config: RAGConfig) async throws -> String {
        // Generate embedding for the query
        let queryEmbedding = try await embeddingBackend.embed(texts: [query]).first ?? []
        
        // Retrieve relevant chunks
        let retrieved = try vectorStore.searchSimilar(for: queryEmbedding, topK: config.topK)
        
        // Build context from retrieved chunks
        let context = buildContextBlock(from: retrieved, includeScores: config.includeScores)
        
        // Create prompt with context
        let prompt = """
        Context:
        \(context)
        
        Question: \(query)
        """
        
        // Build messages for LLM
        let messages: [Message] = [
            Message(role: .system, text: config.systemPrompt),
            Message(role: .user, text: prompt)
        ]
        
        // Stream response from LLM and collect it
        var response = ""
        for await chunk in llm.stream(messages: messages) {
            response += chunk
        }
        
        return response
    }
    
    /// Stream answer with real-time updates
    public func streamAnswer(query: String, config: RAGConfig) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // Generate embedding
                    let queryEmbedding = try await embeddingBackend.embed(texts: [query]).first ?? []
                    
                    // Retrieve chunks
                    let retrieved = try vectorStore.searchSimilar(for: queryEmbedding, topK: config.topK)
                    
                    // Build context
                    let context = buildContextBlock(from: retrieved, includeScores: config.includeScores)
                    
                    // Create prompt
                    let prompt = """
                    Context:
                    \(context)
                    
                    Question: \(query)
                    """
                    
                    // Build messages
                    let messages: [Message] = [
                        Message(role: .system, text: config.systemPrompt),
                        Message(role: .user, text: prompt)
                    ]
                    
                    // Stream from LLM
                    for await chunk in llm.stream(messages: messages) {
                        continuation.yield(chunk)
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    private func buildContextBlock(from chunks: [RetrievedChunk], includeScores: Bool) -> String {
        guard !chunks.isEmpty else { return "No relevant documents found." }
        return chunks.enumerated().map { index, chunk in
            var header = "[\(index + 1)] Source: \(chunk.sourceID)"
            if includeScores {
                header += " (relevance: \(String(format: "%.2f", chunk.score)))"
            }
            return """
            \(header)
            \(chunk.content)
            """
        }.joined(separator: "\n\n")
    }
}
