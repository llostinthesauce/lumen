import Foundation
import os.log
import Combine
import CryptoKit

public struct MessageAttachment: Identifiable, Codable, Hashable {
    public enum AttachmentType: String, Codable {
        case image
        case file
    }
    
    public let id: UUID
    public var type: AttachmentType
    public var filename: String
    public var relativePath: String
    public var fileSize: Int64
    public var contentType: String?
    
    public init(
        id: UUID = UUID(),
        type: AttachmentType,
        filename: String,
        relativePath: String,
        fileSize: Int64,
        contentType: String? = nil
    ) {
        self.id = id
        self.type = type
        self.filename = filename
        self.relativePath = relativePath
        self.fileSize = fileSize
        self.contentType = contentType
    }
}

public struct Message: Identifiable, Codable, Hashable {
    public enum Role: String, Codable { case user, assistant, system }
    public let id: UUID
    public var role: Role
    public var text: String
    public var timestamp: Date
    public var attachments: [MessageAttachment] = []
    public var referencedDocuments: [String]? = nil
    
    public init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        timestamp: Date = Date(),
        attachments: [MessageAttachment] = [],
        referencedDocuments: [String]? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.attachments = attachments
        self.referencedDocuments = referencedDocuments
    }
}

// MARK: - Inference Profile (2.1)
public enum InferenceProfile: String, Codable, CaseIterable {
    case low = "Low"
    case balanced = "Balanced"
    case max = "Max"
    
    private static func maxTokensKey(for profile: InferenceProfile) -> String {
        "inference.profile.maxTokens.\(profile.rawValue)"
    }
    
    /// Context size (in tokens) for this profile
    public var contextSize: Int {
        switch self {
        case .low: return 2048
        case .balanced: return 4096
        case .max: return 8192
        }
    }
    
    /// Default temperature for this profile
    public var temperature: Double {
        switch self {
        case .low: return 0.5
        case .balanced: return 0.7
        case .max: return 0.9
        }
    }
    
    /// Default max tokens for this profile
    public var maxTokens: Int {
        let stored = UserDefaults.standard.integer(forKey: Self.maxTokensKey(for: self))
        if stored > 0 { return stored }
        return defaultMaxTokens
    }
    
    private var defaultMaxTokens: Int {
        #if os(iOS)
        switch self {
        case .low: return 160
        case .balanced: return 320
        case .max: return 640
        }
        #else
        switch self {
        case .low: return 256
        case .balanced: return 512
        case .max: return 1024
        }
        #endif
    }
    
    public static func setMaxTokens(_ value: Int, for profile: InferenceProfile) {
        let clamped = Swift.max(32, Swift.min(value, 4096))
        UserDefaults.standard.set(clamped, forKey: maxTokensKey(for: profile))
    }
    
    /// Default max KV cache size
    public var maxKV: Int {
        #if os(iOS)
        switch self {
        case .low: return 64
        case .balanced: return 160
        case .max: return 256
        }
        #else
        switch self {
        case .low: return 128
        case .balanced: return 256
        case .max: return 512
        }
        #endif
    }
    
    /// Default topP value
    public var topP: Double {
        switch self {
        case .low: return 0.9
        case .balanced: return 0.95
        case .max: return 0.98
        }
    }
    
    /// Create an InferenceConfig from this profile
    public func toConfig() -> InferenceConfig {
        InferenceConfig(
            maxKV: maxKV,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            systemPrompt: "You are a helpful, concise assistant.",
            trustRemoteCode: false,
            profile: self
        )
    }
    
    /// Create an InferenceConfig from this profile, adjusted for model size
    public func toConfig(forModelSize modelSize: ModelSize) -> InferenceConfig {
        var config = toConfig()
        
        // Adjust context size based on model size
        // Smaller models may not support large contexts
        switch modelSize {
        case .small: // < 1B parameters
            config.maxKV = min(maxKV, 128)
            config.maxTokens = min(maxTokens, 256)
        case .medium: // 1-7B parameters
            config.maxKV = min(maxKV, 256)
            config.maxTokens = min(maxTokens, 512)
        case .large: // > 7B parameters
            // Use full profile settings
            break
        }
        
        return config
    }
}

// MARK: - Model Size Helper
public enum ModelSize {
    case small    // < 1B parameters
    case medium   // 1-7B parameters
    case large    // > 7B parameters
    
    /// Estimate model size from model name/ID
    public static func estimate(from modelId: String) -> ModelSize {
        let lowercased = modelId.lowercased()
        
        // Check for explicit size indicators
        if lowercased.contains("135m") || lowercased.contains("270m") || lowercased.contains("0.5b") {
            return .small
        }
        if lowercased.contains("1b") || lowercased.contains("3b") || lowercased.contains("7b") {
            return .medium
        }
        if lowercased.contains("8b") || lowercased.contains("13b") || lowercased.contains("70b") {
            return .large
        }
        
        // Default to medium if unclear
        return .medium
    }
}

public struct InferenceConfig: Codable, Hashable {
    public var maxKV: Int = 256
    public var maxTokens: Int = 256
    public var temperature: Double = 0.7
    public var topP: Double = 0.95
    public var systemPrompt: String = "You are a helpful, concise assistant."
    public var trustRemoteCode: Bool = false
    public var profile: InferenceProfile? = .balanced // 2.1: Optional profile field
    
    public init(maxKV: Int = 256, maxTokens: Int = 256, temperature: Double = 0.7, topP: Double = 0.95, systemPrompt: String = "You are a helpful, concise assistant.", trustRemoteCode: Bool = false, profile: InferenceProfile? = .balanced) {
        self.maxKV = maxKV
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.systemPrompt = systemPrompt
        self.trustRemoteCode = trustRemoteCode
        self.profile = profile
    }
    
    /// Create config from a profile (2.2: Preset factory)
    public static func preset(for profile: InferenceProfile, modelSize: ModelSize = .medium) -> InferenceConfig {
        var config = profile.toConfig(forModelSize: modelSize)
        config.profile = profile
        return config
    }
    
    /// Create config from a profile (backward compatibility)
    public static func from(_ profile: InferenceProfile, modelSize: ModelSize = .medium) -> InferenceConfig {
        preset(for: profile, modelSize: modelSize)
    }
}

public struct ChatStatistics: Codable, Hashable {
    public var totalMessages: Int = 0
    public var userMessages: Int = 0
    public var assistantMessages: Int = 0
    public var totalTokens: Int = 0
    public var estimatedTokens: Int = 0
    public var averageResponseTime: Double = 0.0
    public var totalResponseTime: Double = 0.0
    public var responseCount: Int = 0
    public var createdAt: Date = Date()
    public var lastActivity: Date = Date()

    public mutating func addMessage(_ message: Message, responseTime: Double? = nil) {
        totalMessages += 1
        lastActivity = Date()

        if message.role == .user {
            userMessages += 1
        } else if message.role == .assistant {
            assistantMessages += 1
            if let time = responseTime {
                totalResponseTime += time
                responseCount += 1
                averageResponseTime = totalResponseTime / Double(responseCount)
            }
        }

        // Rough token estimation: ~4 characters per token
        let messageTokens = Int(ceil(Double(message.text.count) / 4.0))
        totalTokens += messageTokens
        estimatedTokens = totalTokens
    }
}

public struct ChatThread: Identifiable, Codable, Hashable {
    public let id: UUID
    public var title: String
    public var modelId: String
    public var messages: [Message]
    public var config: InferenceConfig
    public var statistics: ChatStatistics
    public var useDocumentContext: Bool
    public var workspaceIDs: [UUID]

    private enum CodingKeys: String, CodingKey {
        case id, title, modelId, messages, config, statistics, useDocumentContext, workspaceIDs
    }

    public init(id: UUID = UUID(), title: String, modelId: String, messages: [Message] = [], config: InferenceConfig = .init()) {
        self.id = id
        self.title = title
        self.modelId = modelId
        self.messages = messages
        self.config = config
        self.statistics = ChatStatistics()
        self.useDocumentContext = false
        self.workspaceIDs = []
        // Initialize statistics for existing messages
        for message in messages {
            self.statistics.addMessage(message)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        modelId = try container.decode(String.self, forKey: .modelId)
        
        // Decode messages with timestamp migration
        var decodedMessages = try container.decode([Message].self, forKey: .messages)
        // Ensure all messages have timestamps (migration for old data)
        // If timestamp is missing or is epoch (0), assign current date
        let now = Date()
        for i in decodedMessages.indices {
            let msg = decodedMessages[i]
            if msg.timestamp.timeIntervalSince1970 < 1 {
                decodedMessages[i] = Message(
                    id: msg.id,
                    role: msg.role,
                    text: msg.text,
                    timestamp: now,
                    attachments: msg.attachments
                )
            }
        }
        messages = decodedMessages
        
        config = try container.decode(InferenceConfig.self, forKey: .config)

        // Handle migration: statistics field may not exist in old data
        if let stats = try? container.decode(ChatStatistics.self, forKey: .statistics) {
            statistics = stats
        } else {
            // Initialize statistics for migrated threads
            statistics = ChatStatistics()
            for message in messages {
                statistics.addMessage(message)
            }
        }
        useDocumentContext = (try? container.decode(Bool.self, forKey: .useDocumentContext)) ?? false
        workspaceIDs = (try? container.decode([UUID].self, forKey: .workspaceIDs)) ?? []
    }
}

public enum AppDirs {
    public static var documents: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        #if os(macOS)
        return docs.appendingPathComponent("LumenComposite", isDirectory: true)
        #else
        return docs
        #endif
    }
    public static var chats: URL { documents.appendingPathComponent("Chats", isDirectory: true) }
    public static var attachments: URL {
        let url = documents.appendingPathComponent("Attachments", isDirectory: true)
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }
    /// Models directory - uses ModelStorage for platform-appropriate paths
    public static var models: URL {
        return ModelStorage.shared.modelsURL
    }
    public static var knowledgeBase: URL {
        let url = documents.appendingPathComponent("KnowledgeBase", isDirectory: true)
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }
    public static var blackHole: URL {
        let url = knowledgeBase.appendingPathComponent("BlackHole", isDirectory: true)
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            do {
                try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
                print("✅ Created BlackHole folder at: \(url.path)")
            } catch {
                print("❌ Failed to create BlackHole folder: \(error.localizedDescription)")
            }
        }
        return url
    }
    public static var vectorIndex: URL {
        let url = knowledgeBase.appendingPathComponent("VectorIndex", isDirectory: true)
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url.appendingPathComponent("index.json")
    }
    public static var workspaceMetadata: URL {
        knowledgeBase.appendingPathComponent("workspaces.json")
    }
    public static var ragDatabase: URL {
        knowledgeBase.appendingPathComponent("lumen_rag.sqlite")
    }
    public static var modelDefaults: URL {
        knowledgeBase.appendingPathComponent("model-defaults.json")
    }
}

#if os(macOS)
struct BlackHoleRegistryEntry: Codable {
    let documentID: UUID
    let modificationDate: TimeInterval
}
#endif

public enum PromptBuilder {
    public static func build(messages: [Message], system: String) -> String {
        var parts: [String] = ["System: \(system)"]
        for m in messages {
            switch m.role {
            case .user: parts.append("User: \(m.text)")
            case .assistant: parts.append("Assistant: \(m.text)")
            case .system: parts.append("System: \(m.text)")
            }
        }
        parts.append("Assistant:")
        return parts.joined(separator: "\n")
    }
}

public protocol ChatEngine {
    func loadModel(at url: URL, config: InferenceConfig) async throws
    func unloadModel() async
    func updateConfig(_ config: InferenceConfig)
    func stream(messages: [Message]) -> AsyncStream<String>
    func cancel() async
}

@MainActor
public final class AppState: ObservableObject {
    let kbLogger = Logger(subsystem: "com.lumen.app", category: "KnowledgeBase")
    @Published public var threads: [ChatThread] = [] {
        didSet {
            // Auto-save when threads change (debounced to avoid too many saves) - 3.1: Only if saveChatHistory is enabled
            guard saveChatHistory else { return }
            saveDebounceTask?.cancel()
            saveDebounceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
                guard !Task.isCancelled else { return }
                do {
                    try SecureStorage.saveThreads(threads)
                } catch {
                    // Silently handle Keychain access issues
                }
            }
        }
    }
    @Published public var selectedThreadID: UUID? = nil {
        didSet {
            guard selectedThreadID != oldValue else { return }
            DispatchQueue.main.async { [weak self] in
                self?.alignSelectedThreadConfigWithProfile(force: false)
            }
        }
    }
    @Published public var currentModelURL: URL? = nil
    @Published public var isModelLoaded: Bool = false
    @Published public var currentEngineName: String = "None"
    @Published public var isKnowledgeIndexing: Bool = false
    @Published public var activeProfile: InferenceProfile = .balanced // legacy label for UI
    @Published public var lastTokensPerSecond: Double? = nil
    @Published public var manualOverrideEnabled: Bool {
        didSet {
            UserDefaults.standard.set(manualOverrideEnabled, forKey: Self.manualOverrideEnabledKey)
            alignSelectedThreadConfigWithProfile(force: true)
        }
    }
    @Published public var manualOverrideConfig: InferenceConfig {
        didSet {
            persistManualOverrideConfig()
            if manualOverrideEnabled {
                alignSelectedThreadConfigWithProfile(force: true)
            }
        }
    }
    @Published public var saveChatHistory: Bool = true { // 3.1
        didSet {
            UserDefaults.standard.set(saveChatHistory, forKey: "saveChatHistory")
        }
    }
    @Published public var documents: [UserDocument] = []
    @Published public var documentChunks: [UUID: [DocumentChunk]] = [:]
    #if os(macOS)
    @Published public var codeWorkspaces: [CodeWorkspace] = []
    #endif
    let autoIndexingEnabled = false
    public let engine: ChatEngine
    public let documentLibrary: DocumentLibrary
    public var embeddingClient: EmbeddingClient?
    var ragStore: VectorStore?
    var documentIndexer: DocumentIndexer?
    var ragEmbeddingBackend: EmbeddingBackend?
    @Published public var selectedEmbeddingModelId: String? {
        didSet {
            UserDefaults.standard.set(selectedEmbeddingModelId, forKey: "embedding.modelId")
        }
    }
    var knowledgeIndexingCount = 0
    var queryEmbeddingQueue = DispatchQueue(label: "com.lumen.app.query-embedding", qos: .userInitiated)
    static let knowledgeSnapshotKey = "knowledgeBase.snapshot"
    static let knowledgeSnapshotBuiltKey = "knowledgeBase.snapshotBuilt"
    var lastKnowledgeSnapshot: String?
    var knowledgeIndexBuilt: Bool
    private var saveDebounceTask: Task<Void, Never>? = nil
    private var capabilityCache: [String: ModelCapabilities] = [:]
    var cancellables: Set<AnyCancellable> = []
    private var lastModelUse: Date = .distantPast
    private var modelIdleTask: Task<Void, Never>?
    private let modelIdleTimeout: TimeInterval = 60 // 60 seconds inactivity timeout
    #if os(macOS)
    private let workspacesURL = AppDirs.workspaceMetadata
    var watchers: [UUID: FolderWatcher] = [:]
    var workspaceAccessRevokers: [UUID: () -> Void] = [:]
    #endif
    private let modelDefaultsRegistry: ModelDefaultsRegistry
#if os(macOS)
    @Published public private(set) var blackHoleFolderPath: String = ""
    @Published public var blackHoleEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(blackHoleEnabled, forKey: Self.blackHoleEnabledKey)
            updateBlackHoleWatcherState()
        }
    }
    var blackHoleFolderURL: URL? {
        didSet { blackHoleFolderPath = blackHoleFolderURL?.path ?? "" }
    }
    var blackHoleWatcher: FolderWatcher?
    var blackHoleWatcherTask: Task<Void, Never>?
    var blackHoleRegistry: [String: BlackHoleRegistryEntry] = [:]
    static let blackHoleBookmarkKey = "blackHoleFolderBookmark"
    static let blackHoleEnabledKey = "blackHole.enabled"
    static let blackHoleRegistryKey = "blackHoleRegistry"
#endif

    var codebaseIndexer: CodebaseIndexer?
    private static let manualOverrideEnabledKey = "inference.manualOverride.enabled"
    private static let manualOverrideConfigKey = "inference.manualOverride.config"
    private static let isManualLoadingEnabledKey = "isManualLoadingEnabled"

    public init(engine: ChatEngine, defaultsRegistry: ModelDefaultsRegistry = .shared) {
        self.engine = engine
        self.modelDefaultsRegistry = defaultsRegistry
        self.manualOverrideEnabled = UserDefaults.standard.bool(forKey: Self.manualOverrideEnabledKey)
        // Manual loading disabled by default as per user request

        self.manualOverrideConfig = Self.loadManualOverrideConfig()
        self.selectedEmbeddingModelId = UserDefaults.standard.string(forKey: "embedding.modelId")
        self.documentLibrary = DocumentLibrary()
        self.documents = documentLibrary.documents
        self.documentChunks = documentLibrary.chunksByDocument
        self.lastKnowledgeSnapshot = UserDefaults.standard.string(forKey: Self.knowledgeSnapshotKey)
        let persistedBuilt = UserDefaults.standard.bool(forKey: Self.knowledgeSnapshotBuiltKey)
        self.knowledgeIndexBuilt = persistedBuilt || (self.lastKnowledgeSnapshot != nil)
#if canImport(MLXVLM)
        VLMShim.bootstrap()
#endif
#if canImport(MLXEmbedders)
        // Defer embedder load until manual rebuild/index
        self.embeddingClient = nil
        self.ragEmbeddingBackend = nil
#else
        self.embeddingClient = nil
        self.ragEmbeddingBackend = StubEmbeddingBackend()
#endif
        self.ragStore = try? SQLiteVectorStore(databaseURL: AppDirs.ragDatabase)
        #if os(macOS)
        self.blackHoleEnabled = UserDefaults.standard.bool(forKey: Self.blackHoleEnabledKey)
        #endif
        // Load saveChatHistory preference (3.1)
        self.saveChatHistory = UserDefaults.standard.object(forKey: "saveChatHistory") as? Bool ?? true
        bindDocumentLibrary()
#if os(macOS)
        loadCodeWorkspaces()
        loadBlackHoleConfiguration()
        if autoIndexingEnabled {
            setupWatchers()
        }
        // Auto-load embedding backend on macOS
        Task {
            await loadEmbeddingBackend()
        }
#endif
        // Load saved threads on initialization (only if saveChatHistory is enabled)
        guard saveChatHistory else {
            self.threads = []
            return
        }
        do {
            var savedThreads = try SecureStorage.loadThreads()
            // Initialize statistics for threads that don't have them (migration)
            for i in 0..<savedThreads.count {
                // Re-initialize to ensure statistics are properly set up
                let thread = savedThreads[i]
                savedThreads[i] = ChatThread(id: thread.id, title: thread.title, modelId: thread.modelId, messages: thread.messages, config: thread.config)
            }
            self.threads = savedThreads
            // Select the first thread if available
            if self.selectedThreadID == nil && !savedThreads.isEmpty {
                self.selectedThreadID = savedThreads.first?.id
            }
        } catch {
            // Start with empty threads if loading fails
            self.threads = []
        }
    }

    public var selectedThread: ChatThread? { threads.first { $0.id == selectedThreadID } }
    public func setSelected(_ id: UUID?) { selectedThreadID = id }
    public func addThread(title: String, modelId: String) {
        let config = getCurrentConfig(for: modelId)
        let t = ChatThread(title: title, modelId: modelId, messages: [], config: config)
        threads.append(t)
        selectedThreadID = t.id
    }
    
    // Get or create a thread for a specific model
    public func getOrCreateThread(for modelId: String) -> UUID {
        if let selected = selectedThread, selected.modelId == modelId {
            selectedThreadID = selected.id
            return selected.id
        }
        // Look for existing thread with this model
        if let idx = threads.firstIndex(where: { $0.modelId == modelId }) {
            var thread = threads[idx]
            let desired = getCurrentConfig(for: modelId)
            if thread.config != desired {
                thread.config = desired
                threads[idx] = thread
                if isModelLoaded, selectedThreadID == thread.id {
                    engine.updateConfig(desired)
                }
            }
            selectedThreadID = thread.id
            return thread.id
        }
        // Create new thread with model name as title
        let title = modelId.isEmpty ? "New Chat" : modelId
        let config = getCurrentConfig(for: modelId)
        let t = ChatThread(title: title, modelId: modelId, messages: [], config: config)
        threads.append(t)
        selectedThreadID = t.id
        return t.id
    }
    
    // Update thread title (for renaming)
    public func updateThreadTitle(_ threadId: UUID, to newTitle: String) {
        guard let idx = threads.firstIndex(where: { $0.id == threadId }) else { return }
        var thread = threads[idx]
        thread.title = newTitle.isEmpty ? thread.modelId : newTitle
        threads[idx] = thread
    }
    
    // Auto-generate thread title from first message
    public func updateThreadTitle(from message: Message, threadId: UUID? = nil) {
        guard let targetId = threadId ?? selectedThreadID,
              let idx = threads.firstIndex(where: { $0.id == targetId }) else { return }
        
        var thread = threads[idx]
        // Only update if title matches model name (default) or is empty
        if thread.title == thread.modelId || thread.title == "New Chat" || thread.title.isEmpty {
            let preview = String(message.text.prefix(50))
            thread.title = preview.isEmpty ? thread.modelId : preview
            threads[idx] = thread
        }
    }
    
    public func thread(with id: UUID) -> ChatThread? {
        threads.first { $0.id == id }
    }

    public func unloadCurrentModel() async {
        cancelModelIdleTimer()
        await engine.unloadModel()
        await MainActor.run {
            self.isModelLoaded = false
            self.currentModelURL = nil
        }
    }
    
    public func updateThread(_ threadId: UUID, _ update: (inout ChatThread) -> Void) {
        guard let idx = threads.firstIndex(where: { $0.id == threadId }) else { return }
        var thread = threads[idx]
        update(&thread)
        threads[idx] = thread
    }
    
    public func updateSelected(_ update: (inout ChatThread) -> Void) {
        guard let id = selectedThreadID else { return }
        updateThread(id, update)
    }
    public func deleteThread(_ threadId: UUID) {
        if let thread = threads.first(where: { $0.id == threadId }) {
            purgeAttachments(in: thread)
        }
        threads.removeAll { $0.id == threadId }
        if selectedThreadID == threadId {
            selectedThreadID = threads.first?.id
        }
    }
    
    public func clearAllThreads() {
        threads.forEach { purgeAttachments(in: $0) }
        threads.removeAll()
        selectedThreadID = nil
        // Clear all stored data (3.1: Only if saveChatHistory is enabled)
        if saveChatHistory {
            try? SecureStorage.clearAllData()
        }
        AttachmentStorage.removeAll()
    }
    
    // MARK: - Chat History Persistence Helper (3.1)
    
    /// Persist threads if chat history saving is enabled
    private func persistThreadsIfNeeded() {
        guard saveChatHistory else { return }
        saveDebounceTask?.cancel()
        saveDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
            guard !Task.isCancelled else { return }
            do {
                try SecureStorage.saveThreads(threads)
            } catch {
                // Silently handle Keychain access issues
            }
        }
    }
    
    private static func loadManualOverrideConfig() -> InferenceConfig {
        if let data = UserDefaults.standard.data(forKey: manualOverrideConfigKey),
           let config = try? JSONDecoder().decode(InferenceConfig.self, from: data) {
            var sanitized = config
            sanitized.profile = nil
            return sanitized
        }
        var fallback = InferenceConfig(
            maxKV: 512,
            maxTokens: 768,
            temperature: 0.65,
            topP: 0.9,
            systemPrompt: "You are a helpful, concise assistant.",
            trustRemoteCode: false,
            profile: nil
        )
        fallback.profile = nil
        return fallback
    }
    
    private func persistManualOverrideConfig() {
        if let data = try? JSONEncoder().encode(manualOverrideConfig) {
            UserDefaults.standard.set(data, forKey: Self.manualOverrideConfigKey)
        }
    }
    
    // MARK: - Power Profile Management (2.2, 2.3)
    
    /// Set the active power profile and update thread config (2.3)
    public func setProfile(_ profile: InferenceProfile) {
        activeProfile = profile
        
        alignSelectedThreadConfigWithProfile(force: true)
    }
    
    /// Get the current inference config from model defaults or manual override
    public func getCurrentConfig(for modelId: String) -> InferenceConfig {
        if manualOverrideEnabled {
            return clampedConfig(for: modelId, base: manualOverrideConfig)
        }
        if let config = modelDefaultsRegistry.config(for: modelId) {
            return clampedConfig(for: modelId, base: config)
        }
        let fallback = modelDefaultsRegistry.config(for: "default-config") ?? manualOverrideConfig
        return clampedConfig(for: modelId, base: fallback)
    }

    /// Clamp maxKV/maxTokens to a safe envelope to prevent oversized allocations.
    public func clampedConfig(for modelId: String?, base: InferenceConfig) -> InferenceConfig {
        var cfg = base
        // Conservative caps to avoid Metal buffer over-allocation on mid-tier GPUs (e.g., 8–16 GB).
        // These values are chosen to stay well under the ~9 GB buffer limit observed in MLX metal allocations.
        let kvCap = 4096
        let tokCap = 768
        cfg.maxKV = max(128, min(cfg.maxKV, kvCap))
        cfg.maxTokens = max(128, min(cfg.maxTokens, tokCap))
        return cfg
    }
    
    public func modelType(for modelId: String) -> ModelDefaultsEntry.ModelType? {
        if let entryType = modelDefaultsRegistry.entry(for: modelId)?.type {
            return entryType
        }
        // Fallback: infer from detected format
        let format = getModelFormat(for: modelId)
        return nil
    }

    /// Reseed the on-disk model defaults file from the bundled copy.
    @MainActor
    public func reseedModelDefaults() {
        modelDefaultsRegistry.reseedFromBundle()
    }
    
    private func alignSelectedThreadConfigWithProfile(force: Bool) {
        guard let currentThread = selectedThread else { return }
        let desiredConfig = getCurrentConfig(for: currentThread.modelId)
        var didChange = false
        updateSelected { thread in
            if force || thread.config != desiredConfig {
                thread.config = desiredConfig
                didChange = true
            }
        }
        if didChange, isModelLoaded {
            engine.updateConfig(desiredConfig)
        }
    }
    
    /// Infer model size hint from model ID (2.2)
    private func inferModelSizeHint(for modelId: String?) -> ModelSize? {
        guard let modelId = modelId else { return nil }
        return ModelSize.estimate(from: modelId)
    }
    
    // MARK: - Model Installation Check (4.1)
    
    /// Check if any models are installed
    public var hasModelsInstalled: Bool {
        !listModelFolders().isEmpty
    }
    
    public var configSourceDescription: String {
        manualOverrideEnabled ? "Manual Override" : "Model Defaults"
    }
    // MARK: - Model Discovery
    
    /// List all available model folders
    public func listModelFolders() -> [String] {
        let fm = FileManager.default
        // Removed ModelStorage.shared.ensureModelsDirExists() to prevent empty folder creation on launch
        
        // Helper to check if a directory is a valid model
        func isValidModel(_ directory: URL) -> Bool {
            guard fm.fileExists(atPath: directory.path) else { return false }
            let format = ModelFormatDetector.detectFormat(at: directory)
            if format == .mlx {
                return true
            }
            // Fallback heuristic: treat directories that contain config + safetensors/tokenizer
            guard let contents = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
                return false
            }
            let hasConfig = contents.contains { $0.lastPathComponent.lowercased() == "config.json" }
            let hasTokenizer = contents.contains { $0.lastPathComponent.lowercased() == "tokenizer.json" }
            let hasWeights = contents.contains { $0.pathExtension.lowercased() == "safetensors" || $0.lastPathComponent.lowercased() == "model.safetensors.index.json" }
            return hasConfig && hasTokenizer && hasWeights
        }
        
        var modelNames: Set<String> = []
        func scan(directory: URL, depth: Int, maxDepth: Int = 2) {
            guard depth <= maxDepth,
                  fm.fileExists(atPath: directory.path),
                  let items = try? fm.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]) else {
                return
            }
            for item in items {
                guard let isDir = try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory,
                      isDir == true else {
                    continue
                }
                if isValidModel(item) {
                    modelNames.insert(item.lastPathComponent)
                } else if depth < maxDepth {
                    scan(directory: item, depth: depth + 1, maxDepth: maxDepth)
                }
            }
        }
        
        let roots = ModelStorage.shared.candidateModelRootURLs()
        for root in roots {
            scan(directory: root, depth: 0)
        }
        
        let bundledFolders = ModelStorage.shared.bundledModelFolders()
        for folder in bundledFolders {
            if isValidModel(folder) {
                modelNames.insert(folder.lastPathComponent)
            }
        }
        
        return modelNames.sorted()
    }
    
    /// Find the URL for a model by ID
    public func findModelURL(for modelId: String) -> URL? {
        guard !modelId.isEmpty else { return nil }
        let fm = FileManager.default
        
        // Prefer bundled models shipped with the app (both platforms)
        if let bundled = ModelStorage.shared.bundledModelFolders()
            .first(where: { $0.lastPathComponent == modelId }),
           fm.fileExists(atPath: bundled.path) {
            let format = ModelFormatDetector.detectFormat(at: bundled)
            if format != .unknown {
                return bundled
            }
        }
        
        // Fall back to user-installed models directories (custom + defaults)
        for root in ModelStorage.shared.candidateModelRootURLs() {
            let candidate = root.appendingPathComponent(modelId, isDirectory: true)
            if fm.fileExists(atPath: candidate.path) {
                let format = ModelFormatDetector.detectFormat(at: candidate)
                if format != .unknown {
                    return candidate
                }
            }
            // Also search nested folders to support owner/model layouts (e.g., Hugging Face)
            if let match = try? fm.subpathsOfDirectory(atPath: root.path) {
                for sub in match where sub.lowercased().contains(modelId.lowercased()) {
                    let nested = root.appendingPathComponent(sub, isDirectory: true)
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: nested.path, isDirectory: &isDir), isDir.boolValue {
                        let format = ModelFormatDetector.detectFormat(at: nested)
                        if format != .unknown && nested.lastPathComponent == modelId {
                            return nested
                        }
                    }
                }
            }
        }
        
        return nil
    }
    
    /// Get the format of a model
    public func getModelFormat(for modelId: String) -> ModelFormat {
        guard let modelURL = findModelURL(for: modelId) else {
            return .unknown
        }
        return ModelFormatDetector.detectFormat(at: modelURL)
    }
    
}

extension AppState {
    /// Approximate token count from text length (roughly 4 chars per token; existing stat already uses this ratio).
    public func estimateTokens(from text: String) -> Int {
        Int(ceil(Double(text.count) / 4.0))
    }
}

public extension AppState {
    // MARK: - Auto-Unload Logic
    
    func handleUserActivity() {
        lastModelUse = Date()
        
        // If model is unloaded but we have a selected thread with a model, reload it
        if !isModelLoaded, let modelId = selectedThread?.modelId, !modelId.isEmpty {
            Task {
                try? await loadModel(modelId)
            }
        } else {
            // Reset timer if model is loaded
            scheduleModelAutoUnload()
        }
    }

    func capabilities(for modelId: String) -> ModelCapabilities {
        guard !modelId.isEmpty else { return [] }
        if let cached = capabilityCache[modelId] {
            return cached
        }
        let url = findModelURL(for: modelId)
        let capabilities = ModelCapabilityDetector.capabilities(for: modelId, modelURL: url)
        capabilityCache[modelId] = capabilities
        return capabilities
    }
    
    // MARK: - Manual Model Loading
    
    /// Load a specific model manually
    func loadModel(_ modelId: String) async throws {
        guard let modelURL = findModelURL(for: modelId) else {
            throw NSError(domain: "AppState", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model not found: \(modelId)"])
        }
        
        let config = getCurrentConfig(for: modelId)
        try await engine.loadModel(at: modelURL, config: config)
        
        await MainActor.run {
            self.isModelLoaded = true
            self.currentModelURL = modelURL
        }
        markModelUsed()
    }
    
    /// Record model usage and schedule auto-unload after inactivity.
    public func markModelUsed() {
        lastModelUse = Date()
        scheduleModelAutoUnload()
    }
    
    /// Cancel pending auto-unload (e.g., during active generation).
    public func cancelModelIdleTimer() {
        modelIdleTask?.cancel()
        modelIdleTask = nil
    }
    
    private func scheduleModelAutoUnload() {
        guard isModelLoaded else { return }
        modelIdleTask?.cancel()
        let scheduledAt = lastModelUse
        modelIdleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(modelIdleTimeout * 1_000_000_000))
            guard let self else { return }
            let elapsed = Date().timeIntervalSince(scheduledAt)
            guard elapsed >= modelIdleTimeout else { return }
            await self.unloadCurrentModel()
        }
    }
    
    // MARK: - Embedding Model Status
    
    /// Name of the currently loaded embedding model
    var embeddingModelName: String? {
        guard ragEmbeddingBackend != nil else { return nil }
        return selectedEmbeddingModelId ?? "Default Embedding Model"
    }
    
    /// Whether an embedding model is currently loaded
    var isEmbeddingModelLoaded: Bool {
        ragEmbeddingBackend != nil
    }
    
    /// Load the embedding model manually
    func loadEmbeddingModel() async throws {
        await loadEmbeddingBackend()
    }
    
    /// Manually trigger document indexing
    func manuallyTriggerIndexing() async {
        await rebuildKnowledgeBase()
    }
    
    private func purgeAttachments(in thread: ChatThread) {
        for message in thread.messages {
            for attachment in message.attachments {
                AttachmentStorage.removeAttachment(attachment)
            }
        }
    }
    
    func document(for id: UUID) -> UserDocument? {
        documents.first { $0.id == id }
    }
    
    func logRAGHits(question: String, retrieved: [RetrievedChunk]) {
        #if os(macOS)
        guard !retrieved.isEmpty else {
            kbLogger.log("RAG: No hits for question \(question, privacy: .public)")
            return
        }
        let titles = retrieved.compactMap { chunk -> String? in
            let docIDString = chunk.metadata?["documentID"] as? String
            guard let docID = docIDString.flatMap(UUID.init(uuidString:)) else { return nil }
            return document(for: docID)?.title
        }
        let joinedTitles = titles.joined(separator: ", ")
        kbLogger.log("RAG: \(joinedTitles, privacy: .public) for question \(question, privacy: .public)")
        #else
        _ = question
        _ = retrieved
        #endif
    }
    
    private func logRAGChunks(question: String, chunks: [DocumentChunk]) {
        #if os(macOS)
        guard !chunks.isEmpty else {
            kbLogger.log("RAG: No hits for question \(question, privacy: .public)")
            return
        }
        let titles = chunks.compactMap { document(for: $0.documentID)?.title }
        let joined = titles.joined(separator: ", ")
        kbLogger.log("RAG: \(joined, privacy: .public) for question \(question, privacy: .public)")
        #else
        _ = question
        _ = chunks
        #endif
    }
    
#if os(macOS)
    // MARK: - Black Hole Folder
    
    public func setBlackHoleFolder(_ url: URL) {
        do {
            print("RAG: Setting Black Hole folder to: \(url.path)")
            let data = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: Self.blackHoleBookmarkKey)
            blackHoleFolderURL = url
            blackHoleEnabled = true
            ensureDocumentContextEnabledForAllThreads()
            print("RAG: Black Hole folder set successfully")
        } catch {
            print("Failed to store black hole folder: \(error.localizedDescription)")
        }
    }
    
    public func clearBlackHoleFolder() {
        Task { @MainActor in
            stopBlackHoleWatcher()
            blackHoleFolderURL = nil
            blackHoleEnabled = false
            for entry in blackHoleRegistry.values {
                removeUserDocument(entry.documentID)
            }
            blackHoleRegistry.removeAll()
            saveBlackHoleRegistry()
            UserDefaults.standard.removeObject(forKey: Self.blackHoleBookmarkKey)
            updateBlackHoleWatcherState()
        }
    }
    
    public func rescanBlackHoleFolder() {
        print("RAG: rescanBlackHoleFolder called. Enabled: \(blackHoleEnabled), URL: \(String(describing: blackHoleFolderURL))")
        guard blackHoleEnabled, blackHoleFolderURL != nil else { 
            print("RAG: rescanBlackHoleFolder aborted due to missing config")
            return 
        }
        Task.detached { [weak self] in
            print("RAG: Starting detached ingest task")
            await self?.ingestBlackHoleFolder(fullRescan: true)
        }
    }
    
    private func loadBlackHoleConfiguration() {
        loadBlackHoleRegistry()
        
        // Ensure BlackHole folder exists
        _ = AppDirs.blackHole
        
        guard blackHoleEnabled else { return }
        
        // Check if we already have a bookmark
        guard let data = UserDefaults.standard.data(forKey: Self.blackHoleBookmarkKey) else {
            blackHoleEnabled = false
            return
        }
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
            if stale {
                setBlackHoleFolder(url)
                return
            }
            blackHoleFolderURL = url
            ensureDocumentContextEnabledForAllThreads()
            updateBlackHoleWatcherState()
        } catch {
            print("Failed to load black hole bookmark: \(error.localizedDescription)")
        }
    }
    
    private func startBlackHoleWatcher() {
        guard let folderURL = blackHoleFolderURL else { return }
        stopBlackHoleWatcher()
        let watcher = FolderWatcher(url: folderURL)
        blackHoleWatcher = watcher
        let stream = watcher.events()
        blackHoleWatcherTask = Task.detached(priority: .utility) { [weak self] in
            for await _ in stream {
                await self?.ingestBlackHoleFolder()
            }
        }
    }
    
    func stopBlackHoleWatcher() {
        blackHoleWatcherTask?.cancel()
        blackHoleWatcherTask = nil
        blackHoleWatcher?.stopMonitoring()
        blackHoleWatcher = nil
    }

    public func updateBlackHoleWatcherState() {
        stopBlackHoleWatcher()
        guard blackHoleEnabled, blackHoleFolderURL != nil else { return }
        startBlackHoleWatcher()
    }
    
    private func loadBlackHoleRegistry() {
        guard let data = UserDefaults.standard.data(forKey: Self.blackHoleRegistryKey),
              let registry = try? JSONDecoder().decode([String: BlackHoleRegistryEntry].self, from: data) else {
            blackHoleRegistry = [:]
            return
        }
        blackHoleRegistry = registry
    }
    
    private func ensureDocumentContextEnabledForAllThreads() {
        for idx in threads.indices {
            if !threads[idx].useDocumentContext {
                threads[idx].useDocumentContext = true
            }
        }
    }
    
    private func saveBlackHoleRegistry() {
        if let data = try? JSONEncoder().encode(blackHoleRegistry) {
            UserDefaults.standard.set(data, forKey: Self.blackHoleRegistryKey)
        }
    }
    
    nonisolated private func ingestBlackHoleFolder(fullRescan: Bool = false) async {
        guard let folderURL = await MainActor.run(resultType: URL?.self, body: { self.blackHoleFolderURL }) else { return }
        let fm = FileManager.default
        let accessed = folderURL.startAccessingSecurityScopedResource()
        defer { if accessed { folderURL.stopAccessingSecurityScopedResource() } }
        let propertyKeys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]
        guard let enumerator = fm.enumerator(at: folderURL, includingPropertiesForKeys: propertyKeys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            print("RAG: Failed to create enumerator for \(folderURL.path)")
            return
        }
        print("RAG: Scanning Black Hole folder: \(folderURL.path)")
        var seenPaths: Set<String> = []
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: Set<URLResourceKey>([.isDirectoryKey])),
                  values.isDirectory != true else {
                continue
            }
            print("RAG: Found file: \(fileURL.lastPathComponent)")
            guard AppState.isSupportedBlackHoleFile(fileURL) else { 
                print("RAG: Unsupported file type: \(fileURL.lastPathComponent)")
                continue 
            }
            let path = fileURL.standardizedFileURL.path
            seenPaths.insert(path)
            let modValues = try? fileURL.resourceValues(forKeys: Set<URLResourceKey>([.contentModificationDateKey]))
            let modified = modValues?.contentModificationDate?.timeIntervalSince1970 ?? 0
            let shouldProcess: Bool = await MainActor.run(resultType: Bool.self) {
                if fullRescan { return true }
                guard let entry = self.blackHoleRegistry[path] else { return true }
                return abs(entry.modificationDate - modified) > 0.5
            }
            if !shouldProcess { continue }
            if let entry = await MainActor.run(resultType: BlackHoleRegistryEntry?.self) { self.blackHoleRegistry[path] } {
                await MainActor.run {
                    self.removeUserDocument(entry.documentID)
                    self.blackHoleRegistry.removeValue(forKey: path)
                }
            }
            if let document = await importBlackHoleDocument(from: fileURL) {
                await MainActor.run {
                    self.blackHoleRegistry[path] = BlackHoleRegistryEntry(documentID: document.id, modificationDate: modified)
                    self.saveBlackHoleRegistry()
                }
                await self.indexDocumentForRAG(document)
            }
        }
        await MainActor.run {
            self.removeMissingBlackHoleDocuments(seenPaths: seenPaths)
        }
    }
    
    nonisolated private func importBlackHoleDocument(from url: URL) async -> UserDocument? {
        await MainActor.run {
            do {
                return try self.importUserDocument(from: url)
            } catch {
                print("Black hole import failed: \(error.localizedDescription)")
                return nil
            }
        }
    }
    
    private func removeMissingBlackHoleDocuments(seenPaths: Set<String>) {
        var changed = false
        for (path, entry) in blackHoleRegistry where !seenPaths.contains(path) {
            removeUserDocument(entry.documentID)
            blackHoleRegistry.removeValue(forKey: path)
            changed = true
        }
        if changed {
            saveBlackHoleRegistry()
        }
    }
    
    private static let blackHoleAllowedExtensions: Set<String> = [
        "txt", "md", "markdown", "rtf", "rtfd", "pdf", "doc", "docx", "html"
    ]
    
    nonisolated private static func isSupportedBlackHoleFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return blackHoleAllowedExtensions.contains(ext)
    }
#endif

#if os(macOS)
    // MARK: - File Watcher Management
    
    private func setupWatchers() {
        for workspace in codeWorkspaces where workspace.isWatching {
            startWatching(workspace)
        }
    }
    
    public func toggleWatch(for workspaceID: UUID) {
        guard let idx = codeWorkspaces.firstIndex(where: { $0.id == workspaceID }) else { return }
        var workspace = codeWorkspaces[idx]
        workspace.isWatching.toggle()
        codeWorkspaces[idx] = workspace
        
        if workspace.isWatching {
            startWatching(workspace)
        } else {
            stopWatching(workspace)
        }
        saveCodeWorkspaces()
    }
    
    private func startWatching(_ workspace: CodeWorkspace) {
        guard watchers[workspace.id] == nil else { return }
        let handle = workspace.scopedURLHandle()
        let watcher = FolderWatcher(url: handle.url)
        
        // Start consuming events
        Task { [weak self] in
            for await _ in watcher.events() {
                guard let self = self else { return }
                // Double check workspace is still being watched
                if self.watchers[workspace.id] != nil {
                    if let latest = self.codeWorkspaces.first(where: { $0.id == workspace.id }) {
                        await self.reindexWorkspace(latest)
                    }
                }
            }
        }
        
        watchers[workspace.id] = watcher
        workspaceAccessRevokers[workspace.id] = handle.revoke
    }
    
    func stopWatching(_ workspace: CodeWorkspace) {
        watchers[workspace.id]?.stopMonitoring()
        watchers[workspace.id] = nil
        workspaceAccessRevokers[workspace.id]?()
        workspaceAccessRevokers.removeValue(forKey: workspace.id)
    }
    
    public func reindexWorkspace(_ workspace: CodeWorkspace, preScannedDocs: [URL: UserDocument]? = nil) {
        guard let indexer = codebaseIndexer else { return }
        isKnowledgeIndexing = true
        Task {
            do {
                let docs: [URL: UserDocument]
                if let preScannedDocs {
                    docs = preScannedDocs
                } else {
                    docs = await MainActor.run { self.scanWorkspace(workspace) }
                }
                let result = try await indexer.indexWorkspace(workspace, documentMap: docs)
                await MainActor.run {
                    self.isKnowledgeIndexing = false
                    self.persistCurrentKnowledgeSnapshot()
                }
                print("Workspace indexing complete: \(result.summary)")
            } catch {
                print("Error indexing workspace: \(error.localizedDescription)")
                await MainActor.run {
                    self.isKnowledgeIndexing = false
                }
            }
        }
    }
    
    // MARK: - Code Workspaces
    
    private func loadCodeWorkspaces() {
        guard let data = try? Data(contentsOf: workspacesURL),
              let loaded = try? JSONDecoder().decode([CodeWorkspace].self, from: data) else {
            return
        }
        self.codeWorkspaces = loaded
    }
    
    func saveCodeWorkspaces() {
        if let data = try? JSONEncoder().encode(codeWorkspaces) {
            try? data.write(to: workspacesURL)
        }
    }
    
    public func addCodeWorkspace(at url: URL) {
        let name = url.lastPathComponent
        let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        let workspace = CodeWorkspace(name: name, rootURL: url, bookmarkData: bookmark)
        codeWorkspaces.append(workspace)
        saveCodeWorkspaces()
        let docs = scanWorkspace(workspace)
        reindexWorkspace(workspace, preScannedDocs: docs)
    }
    
    @discardableResult
    public func scanWorkspace(_ workspace: CodeWorkspace) -> [URL: UserDocument] {
        documentLibrary.purgeCodeDocuments(for: workspace.id)
        let fm = FileManager.default
        return (try? workspace.withSecurityScopedAccess { secureURL in
            var documentMap: [URL: UserDocument] = [:]
            guard let enumerator = fm.enumerator(at: secureURL,
                                                 includingPropertiesForKeys: [.isRegularFileKey],
                                                 options: [.skipsHiddenFiles]) else {
                return documentMap
            }
        let allowedExtensions: Set<String> = ["swift", "m", "mm", "py", "js", "ts", "tsx", "jsx", "java", "kt", "rb", "rs", "c", "cc", "cpp", "h", "hpp"]
        
        for case let fileURL as URL in enumerator {
            if shouldIgnore(fileURL.path, ignorePatterns: workspace.ignorePatterns) { continue }
            let ext = fileURL.pathExtension.lowercased()
            guard allowedExtensions.contains(ext) else { continue }
            guard let isRegular = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile,
                  isRegular == true else { continue }
            let relativePath = fileURL.path.replacingOccurrences(of: secureURL.path + "/", with: "")
            let document = documentLibrary.registerCodeDocument(fileURL: fileURL, title: relativePath, workspaceID: workspace.id)
            documentMap[fileURL] = document
        }
        documentLibrary.persist()
        saveCodeWorkspaces()
            return documentMap
        }) ?? [:]
    }
    
    private func shouldIgnore(_ path: String, ignorePatterns: [String]) -> Bool {
        for pattern in ignorePatterns {
            if path.contains(pattern) { return true }
        }
        return false
    }

    public func removeCodeWorkspace(_ workspaceID: UUID) {
        guard let idx = codeWorkspaces.firstIndex(where: { $0.id == workspaceID }) else { return }
        let workspace = codeWorkspaces[idx]
        stopWatching(workspace)
        codeWorkspaces.remove(at: idx)
        saveCodeWorkspaces()
        let docs = documentLibrary.documents.filter { $0.workspaceID == workspaceID }
        documentLibrary.purgeCodeDocuments(for: workspaceID)
        Task {
            for doc in docs {
                let relativePath = doc.fileURL.path.replacingOccurrences(of: workspace.rootURL.path, with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let sourceID = "file://\(workspace.id.uuidString)/\(relativePath)"
                try? self.ragStore?.deleteChunks(for: sourceID)
            }
        }
    }
    
    public func updateWorkspace(_ workspaceID: UUID, name: String, languages: [String], ignorePatterns: [String]) {
        guard let idx = codeWorkspaces.firstIndex(where: { $0.id == workspaceID }) else { return }
        var workspace = codeWorkspaces[idx]
        workspace.name = name.isEmpty ? workspace.name : name
        workspace.languages = languages
        workspace.ignorePatterns = ignorePatterns
        workspace.updatedAt = Date()
        codeWorkspaces[idx] = workspace
        saveCodeWorkspaces()
        let docs = scanWorkspace(workspace)
        reindexWorkspace(workspace, preScannedDocs: docs)
    }
#endif
    
}

// MARK: - Secure Chat Storage
public enum SecureStorage {
    private static let serviceName = "com.lumen.app"
    private static let encryptionKeyKey = "com.lumen.encryptionKey"
    private static let threadsKey = "com.lumen.threads"

    // Get or create encryption key
    private static func getEncryptionKey() throws -> SymmetricKey {
        // Try to get existing key from Keychain
        if let keyData = try? KeychainHelper.getData(forKey: encryptionKeyKey) {
            let key = SymmetricKey(data: keyData) // not throwing
            return key
        }

        // Generate new key and store it
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        try KeychainHelper.saveData(keyData, forKey: encryptionKeyKey)
        return key
    }

    // Encrypt data
    private static func encrypt(_ data: Data) throws -> Data {
        let key = try getEncryptionKey()
        return try AES.GCM.seal(data, using: key).combined!
    }

    // Decrypt data
    private static func decrypt(_ data: Data) throws -> Data {
        let key = try getEncryptionKey()
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: key)
    }

    // Save threads securely
    public static func saveThreads(_ threads: [ChatThread]) throws {
        let data = try JSONEncoder().encode(threads)
        let encryptedData = try encrypt(data)
        try KeychainHelper.saveData(encryptedData, forKey: threadsKey)
    }

    // Load threads securely
    public static func loadThreads() throws -> [ChatThread] {
        guard let encryptedData = try? KeychainHelper.getData(forKey: threadsKey) else {
            return []
        }
        let decryptedData = try decrypt(encryptedData)
        return try JSONDecoder().decode([ChatThread].self, from: decryptedData)
    }

    // Clear all stored data
    public static func clearAllData() throws {
        try? KeychainHelper.deleteData(forKey: encryptionKeyKey)
        try? KeychainHelper.deleteData(forKey: threadsKey)
    }
}

// MARK: - Keychain Helper
private enum KeychainHelper {
    private static let serviceName = "com.lumen.app"
    
    static func saveData(_ data: Data, forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        // Delete existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            let error = NSError(domain: "KeychainError", code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "Keychain save failed with error code: \(status)"
            ])
            throw error
        }
    }

    static func getData(forKey key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess {
            return result as? Data
        } else if status == errSecItemNotFound {
            return nil
        } else {
            let error = NSError(domain: "KeychainError", code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "Keychain read failed with error code: \(status)"
            ])
            throw error
        }
    }

    static func deleteData(forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            let error = NSError(domain: "KeychainError", code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "Keychain delete failed with error code: \(status)"
            ])
            throw error
        }
    }
}
