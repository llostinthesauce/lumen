import Foundation

/// Multi-engine router that currently wraps only the MLX engine.
/// This preserves the architecture while focusing development on a single implementation.
public final class MultiEngine: ChatEngine {
    public enum ModelState {
        case idle
        case loading(URL)
        case loaded(URL)
        case unloading
        case error(Error)
    }
    
    public enum EngineError: LocalizedError {
        case modelAlreadyLoading
        case operationInProgress
        case noModelLoaded
        
        public var errorDescription: String? {
            switch self {
            case .modelAlreadyLoading:
                return "A model is already being loaded. Please wait for the current operation to complete."
            case .operationInProgress:
                return "An operation is in progress. Please wait before performing another action."
            case .noModelLoaded:
                return "No model is currently loaded."
            }
        }
    }
    
    private let mlxEngine: MlxEngine
    private var currentModelURL: URL?
    private var config: InferenceConfig = .init()
    private var state: ModelState = .idle
    private let stateLock = NSLock()
    
    public init() {
        self.mlxEngine = MlxEngine()
    }
    
    public var currentState: ModelState {
        stateLock.lock()
        defer { stateLock.unlock() }
        return state
    }
    
    public func loadModel(at url: URL, config: InferenceConfig) async throws {
        // Check and update state atomically
        stateLock.lock()
        switch state {
        case .loading:
            stateLock.unlock()
            throw EngineError.modelAlreadyLoading
        case .unloading:
            stateLock.unlock()
            throw EngineError.operationInProgress
        case .idle, .loaded, .error:
            state = .loading(url)
            stateLock.unlock()
        }
        
        do {
            self.config = config
            try await mlxEngine.loadModel(at: url, config: config)
            
            stateLock.lock()
            self.currentModelURL = url
            state = .loaded(url)
            stateLock.unlock()
        } catch {
            stateLock.lock()
            state = .error(error)
            stateLock.unlock()
            throw error
        }
    }
    
    public func unloadModel() async {
        stateLock.lock()
        guard case .loaded = state else {
            stateLock.unlock()
            return
        }
        state = .unloading
        stateLock.unlock()
        
        await mlxEngine.unloadModel()
        
        stateLock.lock()
        self.currentModelURL = nil
        state = .idle
        stateLock.unlock()
    }
    
    public func updateConfig(_ config: InferenceConfig) {
        self.config = config
        mlxEngine.updateConfig(config)
    }
    
    public func stream(messages: [Message]) -> AsyncStream<String> {
        return mlxEngine.stream(messages: messages)
    }
    
    public func cancel() async {
        await mlxEngine.cancel()
    }
    
    public func currentEngineName() -> String {
        "MLX"
    }
}
