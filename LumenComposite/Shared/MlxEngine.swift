import Foundation

// Native MLX Swift imports (works on both iOS and macOS)
#if canImport(MLX)
import MLX
#endif
#if canImport(MLXLLM)
import MLXLLM
#endif
#if canImport(MLXLMCommon)
import MLXLMCommon
#endif
#if canImport(Hub)
import Hub
#endif

public final class MlxEngine: ChatEngine {
    private var modelURL: URL?
    private var config: InferenceConfig = .init()
    private var loadingTask: Task<Void, Error>?
    private var generationTask: Task<Void, Never>?
    nonisolated(unsafe) private var isCancelled = false
    
    // Native MLX Swift model container
    private var modelContainer: ModelContainer?
    
    public init() {}

    public func loadModel(at url: URL, config: InferenceConfig) async throws {
        print("[MLX] Loading model at \(url.lastPathComponent) with config maxKV=\(config.maxKV) maxTokens=\(config.maxTokens)")
        let fm = FileManager.default
        var isDirectory: ObjCBool = false

        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw NSError(domain: "MlxEngine", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "Model directory not found at \(url.path)"
            ])
        }
        
        // If we are already loading this exact model, wait for it
        if let loadingTask = loadingTask, self.modelURL == url {
            return try await loadingTask.value
        }
        
        // Cancel any existing tasks
        loadingTask?.cancel()
        generationTask?.cancel()
        loadingTask = nil
        generationTask = nil
        
        // If we have a model loaded that is NOT the one we want, unload it first
        if modelContainer != nil && self.modelURL != url {
            await unloadModel()
        }
        
        let task = Task.detached {
            #if canImport(MLXLLM) && canImport(MLXLMCommon)
            let container = try await MlxEngine.loadContainer(at: url)
            await MainActor.run {
                self.modelContainer = container
            }
            #else
            throw NSError(domain: "MlxEngine", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "MLX Swift libraries not available"
            ])
            #endif
        }
        loadingTask = task
        
        self.modelURL = url
        self.config = config
        self.isCancelled = false
        
        try await task.value
        loadingTask = nil
    }
    
    public func unloadModel() async {
        print("[MLX] Unloading model")
        loadingTask?.cancel()
        generationTask?.cancel()
        loadingTask = nil
        generationTask = nil
        modelContainer = nil
        modelURL = nil
    }
    
    #if canImport(MLXLLM) && canImport(MLXLMCommon)
    private static func loadContainer(at url: URL) async throws -> ModelContainer {
        // Set GPU memory limit (larger cache for better performance)
        MLX.GPU.set(cacheLimit: 100 * 1024 * 1024) // 100MB cache
        
        // Verify config.json exists before creating ModelConfiguration
        let fm = FileManager.default
        let configURL = url.appendingPathComponent("config.json")
        
        // Check if config.json exists in root, or search for it
        var configPath = url
        
        if !fm.fileExists(atPath: configURL.path) {
            // Try to find config.json in subdirectories
            if let found = findConfigJSON(in: url) {
                configPath = found.deletingLastPathComponent()
            } else {
                // List files found for better error message
                var foundFiles: [String] = []
                if let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey], options: [.skipsHiddenFiles]) {
                    for item in contents {
                        let resourceValues = try? item.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
                        if resourceValues?.isRegularFile == true {
                            foundFiles.append(item.lastPathComponent)
                        } else if resourceValues?.isDirectory == true {
                            foundFiles.append("\(item.lastPathComponent)/")
                        }
                    }
                }
                let filesList = foundFiles.isEmpty ? "No files found" : foundFiles.joined(separator: ", ")
                throw NSError(domain: "MlxEngine", code: 404, userInfo: [
                    NSLocalizedDescriptionKey: "config.json not found in model directory at \(url.path). Found files: \(filesList)"
                ])
            }
        }
        
        let hub = HubApi()
        
        // Verify safetensors files exist before loading
        let safetensorsFiles = try? fm.contentsOfDirectory(at: configPath, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])
            .filter { $0.pathExtension == "safetensors" }
        
        if safetensorsFiles?.isEmpty == true {
             throw NSError(domain: "MlxEngine", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "No .safetensors files found in model directory at \(configPath.path)"
            ])
        }
        
        let configuration = ModelConfiguration(directory: configPath)
        
        // Use loadModelContainer from MLXLMCommon
        return try await MLXLMCommon.loadModelContainer(hub: hub, configuration: configuration) { progress in
            // Progress handling if needed
        }
    }
    
    // Helper to find config.json recursively
    private static func findConfigJSON(in directory: URL) -> URL? {
        let fm = FileManager.default
        // Try with and without skipsHiddenFiles - some iOS file systems might hide files differently
        let options: [FileManager.DirectoryEnumerationOptions] = [[], [.skipsHiddenFiles]]
        
        for optionSet in options {
            guard let contents = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey], options: optionSet) else {
                continue
            }
            
            for item in contents {
                let resourceValues = try? item.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
                let isDir = resourceValues?.isDirectory ?? false
                let isFile = resourceValues?.isRegularFile ?? false
                
                let fileName = item.lastPathComponent
                
                if isFile {
                    // Check exact match first, then case-insensitive
                    if fileName == "config.json" || fileName.lowercased() == "config.json" {
                        return item
                    }
                } else if isDir {
                    // Skip common system directories
                    if !fileName.hasPrefix(".") && !fileName.hasPrefix("__MACOSX") {
                        // Recursively search subdirectories
                        if let found = findConfigJSON(in: item) {
                            return found
                        }
                    }
                }
            }
        }
        
        return nil
    }
    #endif
    
    public func updateConfig(_ config: InferenceConfig) {
        self.config = config
    }

    public func stream(messages: [Message]) -> AsyncStream<String> {
        let cfg = self.config
        isCancelled = false

        return AsyncStream { continuation in
            let task = Task {
                do {
                    #if canImport(MLXLLM) && canImport(MLXLMCommon)
                    // Use native MLX Swift (works on both iOS and macOS)
                    if let container = self.modelContainer {
                        try await self.generateWithMLXSwift(
                            container: container,
                            messages: messages,
                            config: cfg,
                            continuation: continuation
                        )
                    } else {
                        continuation.yield("Error: Model not loaded. Please load a model first.")
                        continuation.finish()
                    }
                    #else
                    continuation.yield("Error: MLX Swift not available on this platform.")
                    continuation.finish()
                    #endif
                } catch {
                    continuation.yield("Error: \(error.localizedDescription)")
                    continuation.finish()
                }
            }
            self.generationTask = task
        }
    }

    public func cancel() async {
        isCancelled = true
        loadingTask?.cancel()
        generationTask?.cancel()
    }
    
    // MARK: - Native MLX Swift Implementation (Primary - iOS and macOS)
    
    #if canImport(MLXLLM) && canImport(MLXLMCommon)
    private func generateWithMLXSwift(
        container: ModelContainer,
        messages: [Message],
        config: InferenceConfig,
        continuation: AsyncStream<String>.Continuation
    ) async throws {
        // Build chat messages - include system prompt if provided
        var chatMessages: [Chat.Message] = []
        
        // Add system prompt if configured and not already in messages
        if !config.systemPrompt.isEmpty && !messages.contains(where: { $0.role == .system }) {
            chatMessages.append(.system(config.systemPrompt))
        }
        
        // Convert our Message format to MLXLMCommon Chat.Message format
        for message in messages {
            let role: Chat.Message.Role = switch message.role {
            case .user:
                .user
            case .assistant:
                .assistant
            case .system:
                .system
            }
            
            let images: [UserInput.Image] = message.attachments.compactMap { attachment in
                guard attachment.type == .image else { return nil }
                return .url(attachment.url)
            }
            var content = message.text.isEmpty && !images.isEmpty ? " " : message.text
            let fileSnippets = message.attachments
                .filter { $0.type == .file }
                .compactMap { attachment -> String? in
                    guard let extracted = AttachmentStorage.textContent(for: attachment) else { return nil }
                    return "Attachment: \(attachment.filename)\n\(extracted)"
                }
            if !fileSnippets.isEmpty {
                let supplement = fileSnippets.joined(separator: "\n\n-----\n")
                if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    content = supplement
                } else {
                    content += "\n\n-----\n" + supplement
                }
            }
            chatMessages.append(Chat.Message(role: role, content: content, images: images))
        }
        
        // Create user input
        let userInput = UserInput(
            chat: chatMessages,
            processing: .init(resize: .init(width: 512, height: 512))
        )
        
        // Set generation parameters
        let generateParams = GenerateParameters(
            maxTokens: config.maxTokens,
            maxKVSize: config.maxKV > 0 ? config.maxKV : nil,
            temperature: Float(config.temperature),
            topP: Float(config.topP)
        )
        
        // Generate using the model container
        do {
            try await container.perform { context in
                // Prepare input
                let lmInput = try await context.processor.prepare(input: userInput)
                
                // Create cache
                let cache = context.model.newCache(parameters: generateParams)
                
                // Generate and stream tokens
                for try await item in try MLXLMCommon.generate(
                    input: lmInput,
                    cache: cache,
                    parameters: generateParams,
                    context: context
                ) {
                    if Task.isCancelled || self.isCancelled {
                        break
                    }
                    
                    // Yield the text chunk
                    if let chunk = item.chunk {
                        continuation.yield(chunk)
                    }
                }
                
                // Synchronize GPU
                Stream.gpu.synchronize()
            }
            
            continuation.finish()
        } catch {
            continuation.yield("Error: \(error.localizedDescription)")
            continuation.finish()
            throw error
        }
    }
    #endif
}
