import Foundation

public protocol EmbeddingBackend {
    func embed(texts: [String]) async throws -> [[Float]]
    var embeddingDimension: Int? { get async }
}

public final class StubEmbeddingBackend: EmbeddingBackend {
    public init() {}
    
    public var embeddingDimension: Int? {
        get async { nil }
    }
    
    public func embed(texts: [String]) async throws -> [[Float]] {
        return texts.map { _ in [] }
    }
}

#if canImport(MLXEmbedders)
import Hub
import MLX
import MLXEmbedders
import MLXNN
import Tokenizers

public actor MLXEmbeddingBackend: EmbeddingBackend {
    private let impl: GenericMLXEmbeddingBackend
    
    public init(
        modelId: String = "bge-small-en-v1.5-bf16",
        normalize: Bool = true,
        applyLayerNorm: Bool = false
    ) {
        self.impl = GenericMLXEmbeddingBackend(modelId: modelId, normalize: normalize, applyLayerNorm: applyLayerNorm)
    }
    
    public var embeddingDimension: Int? {
        get async { await impl.embeddingDimension }
    }
    
    public func embed(texts: [String]) async throws -> [[Float]] {
        return try await impl.embed(texts: texts)
    }
}

public actor GenericMLXEmbeddingBackend: EmbeddingBackend {
    public enum BackendError: LocalizedError {
        case missingPadToken
        case noUsableTokens
        case unsupportedShape([Int])
        case modelNotFound(attempted: [String])
        case offlineModeNoLocalModel(modelId: String)
        
        public var errorDescription: String? {
            switch self {
            case .missingPadToken:
                return "Embedding model is missing pad token configuration"
            case .noUsableTokens:
                return "No valid tokens could be encoded from input text"
            case .unsupportedShape(let shape):
                return "Unexpected embedding output shape: \(shape)"
            case .modelNotFound(let attempted):
                let list = attempted.joined(separator: ", ")
                return "Failed to load embedding model. Attempted: \(list).\n\nPlease ensure an embedding model is installed in BundledModels or Models directory."
            case .offlineModeNoLocalModel(let modelId):
                return "Offline mode: Embedding model '\(modelId)' not found locally. Please add the model to BundledModels directory."
            }
        }
    }
    
    private var modelId: String
    private let normalize: Bool
    private let applyLayerNorm: Bool
    private let configuration: ModelConfiguration
    private var container: ModelContainer?
    private let fallbackModelIds = [
        "bge-small-en-v1.5-bf16",
        "mlx-community/bge-small-en-v1.5-bf16"
    ]
    private let strictOfflineMode: Bool  // Prevent network downloads
    
    public init(
        modelId: String = "embeddinggemma-300m-bf16",
        normalize: Bool = true,
        applyLayerNorm: Bool = false,
        strictOfflineMode: Bool = true  // Default to offline for privacy
    ) {
        self.modelId = modelId
        self.normalize = normalize
        self.applyLayerNorm = applyLayerNorm
        self.strictOfflineMode = strictOfflineMode
        self.configuration = GenericMLXEmbeddingBackend.makeConfiguration(for: modelId)
    }
    
    public var embeddingDimension: Int? {
        get async {
            guard let container = try? await ensureContainer() else { return nil }
            // Try to get dimension from a small test embedding
            if let result = try? await container.perform({ (model, tokenizer, pooler) -> Int? in
                let testTokens = tokenizer.encode(text: "test", addSpecialTokens: true)
                guard !testTokens.isEmpty else { return nil }
                let padToken = tokenizer.eosTokenId ?? 0
                let input = MLXArray(testTokens)
                let mask = (input .!= padToken)
                let tokenTypes = MLXArray.zeros(like: input)
                let outputs = model(
                    input.reshaped([1, testTokens.count]),
                    positionIds: nil,
                    tokenTypeIds: tokenTypes.reshaped([1, testTokens.count]),
                    attentionMask: mask.reshaped([1, testTokens.count])
                )
                let poolingModule = GenericMLXEmbeddingBackend.resolvedPooler(pooler, override: nil)
                var pooled = poolingModule(
                    outputs,
                    mask: mask.reshaped([1, testTokens.count]),
                    normalize: self.normalize,
                    applyLayerNorm: self.applyLayerNorm
                )
                pooled.eval()
                let shape = pooled.shape.map { Int($0) }
                return shape.last
            }) {
                return result
            }
            return nil
        }
    }
    
    public func embed(texts: [String]) async throws -> [[Float]] {
        guard !texts.isEmpty else { return [] }
        let container = try await ensureContainer()
        let poolerStrategy = poolerOverride()
        return try await container.perform { model, tokenizer, pooler in
            var encoded: [(Int, [Int])] = []
            for (index, text) in texts.enumerated() {
                let tokens = tokenizer.encode(text: text, addSpecialTokens: true)
                if !tokens.isEmpty {
                    encoded.append((index, tokens))
                }
            }
            guard !encoded.isEmpty else {
                throw BackendError.noUsableTokens
            }
            let padToken = tokenizer.eosTokenId ?? 0
            let maxLength = encoded.map { $0.1.count }.max() ?? 0
            let padded = stacked(
                encoded.map { _, tokens in
                    MLXArray(tokens + Array(repeating: padToken, count: maxLength - tokens.count))
                })
            let mask = (padded .!= padToken)
            let tokenTypes = MLXArray.zeros(like: padded)
            let outputs = model(
                padded,
                positionIds: nil,
                tokenTypeIds: tokenTypes,
                attentionMask: mask
            )
            let poolingModule = GenericMLXEmbeddingBackend.resolvedPooler(pooler, override: poolerStrategy)
            var pooled = poolingModule(
                outputs,
                mask: mask,
                normalize: normalize,
                applyLayerNorm: applyLayerNorm
            )
            pooled.eval()
            let shape = pooled.shape.map { Int($0) }
            guard shape.count == 2, let dim = shape.last else {
                throw BackendError.unsupportedShape(shape)
            }
            let flattened = pooled.asArray(Float.self)
            var vectors = Array(repeating: [Float](), count: texts.count)
            for (batchIndex, (originalIndex, _)) in encoded.enumerated() {
                let start = batchIndex * dim
                guard start + dim <= flattened.count else { continue }
                let slice = Array(flattened[start ..< start + dim])
                vectors[originalIndex] = slice
            }
            return vectors
        }
    }
    
    private static func resolvedPooler(_ pooler: Pooling, override: Pooling.Strategy?) -> Pooling {
        if pooler.strategy == .none {
            if let dimension = pooler.dimension {
                return Pooling(strategy: .mean, dimension: dimension)
            }
            return Pooling(strategy: .mean)
        }
        return pooler
    }
    
    private nonisolated func poolerOverride() -> Pooling.Strategy? { nil }
    
    private func ensureContainer() async throws -> ModelContainer {
        if let container { return container }
        
        // Try primary model; on failure, attempt fallbacks before giving up.
        var attempted: [String] = []
        let candidates = [modelId] + fallbackModelIds.filter { $0 != modelId }
        
        var lastError: Error?
        for candidate in candidates {
            attempted.append(candidate)
            do {
                let config = GenericMLXEmbeddingBackend.makeConfiguration(for: candidate)
                let newContainer = try await MLXEmbedders.loadModelContainer(
                    hub: HubApi(),
                    configuration: config
                )
                self.container = newContainer
                self.modelId = candidate
                return newContainer
            } catch {
                lastError = error
                continue
            }
        }
        let attemptedList = attempted.joined(separator: ", ")
        throw lastError ?? NSError(
            domain: "EmbeddingBackend",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Failed to load any embedding model. Attempted: \(attemptedList)"]
        )
    }
    
    private static func makeConfiguration(for modelId: String) -> ModelConfiguration {
        // Always prefer bundled models
        if let bundled = ModelStorage.shared.bundledModelFolders()
            .first(where: { $0.lastPathComponent == modelId }) {
            return ModelConfiguration(directory: bundled)
        }
        
        // Check user models directory
        let modelsURL = ModelStorage.shared.modelsURL.appendingPathComponent(modelId, isDirectory: true)
        if FileManager.default.fileExists(atPath: modelsURL.path) {
            return ModelConfiguration(directory: modelsURL)
        }
        
        // For strict offline mode, this will fail - no network fallback
        return ModelConfiguration(id: modelId)
    }
}
#endif
