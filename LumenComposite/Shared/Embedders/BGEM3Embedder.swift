import Foundation

#if canImport(MLXEmbedders)
/// Convenience wrapper that configures the generic MLX embedding backend with the
/// defaults required for the bundled BGE M3 embedding model.
///
/// The older implementation of this type depended on APIs that were removed from
/// MLX and Tokenizers, which caused a cascade of build failures.  This trimmed
/// down actor relies on `GenericMLXEmbeddingBackend`, ensuring we only use the
/// currently supported surface area.
public actor BGEM3Embedder: EmbeddingBackend {
    private let backend: GenericMLXEmbeddingBackend

    public init(
        modelId: String = "bge-m3",
        normalize: Bool = true,
        applyLayerNorm: Bool = false
    ) {
        self.backend = GenericMLXEmbeddingBackend(
            modelId: modelId,
            normalize: normalize,
            applyLayerNorm: applyLayerNorm
        )
    }
    
    public var embeddingDimension: Int? {
        get async { await backend.embeddingDimension }
    }

    public func embed(texts: [String]) async throws -> [[Float]] {
        try await backend.embed(texts: texts)
    }
}
#endif
