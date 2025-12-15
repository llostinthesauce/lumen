import Foundation

public protocol EmbeddingClient {
    func embed(texts: [String]) async throws -> [[Double]]
}

public final class EmbeddingClientAdapter: EmbeddingClient {
    private let backend: any EmbeddingBackend

    public init(backend: any EmbeddingBackend) {
        self.backend = backend
    }

    public func embed(texts: [String]) async throws -> [[Double]] {
        let vectors = try await backend.embed(texts: texts)
        return vectors.map { $0.map { Double($0) } }
    }
}
