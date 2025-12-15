import Foundation
import SwiftUI
import Combine

@MainActor
public final class ChatSessionController: ObservableObject {
    @Published var isStreaming: Bool = false
    @Published var isLoadingModel: Bool = false
    @Published var streamText: String = ""
    @Published var filteredStreamText: String = ""
    @Published var errorMessage: String?
    @Published var showError: Bool = false
    @Published private(set) var currentTokenHint: String = ""
    @Published private(set) var activeStreamingThreadID: UUID?
    
    private let state: AppState
    
    init(state: AppState) {
        self.state = state
        updateTokenHint()
    }
    
    func send(text: String, selectedModel: String, attachments: [MessageAttachment] = []) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var modelId = selectedModel
        if modelId.isEmpty {
            modelId = state.selectedThread?.modelId ?? ""
        }
        
        guard !modelId.isEmpty else {
            presentError("No model selected. Please select a model from the sidebar.")
            return
        }
        
        let threadId = state.getOrCreateThread(for: modelId)
        activeStreamingThreadID = threadId
        state.selectedThreadID = threadId
        
        let userMessage = Message(role: .user, text: trimmed, attachments: attachments)
        state.updateThread(threadId) { thread in
            thread.messages.append(userMessage)
            thread.statistics.addMessage(userMessage)
        }
        state.updateThreadTitle(from: userMessage, threadId: threadId)
        state.cancelModelIdleTimer()
        
        streamText = ""
        filteredStreamText = ""
        isStreaming = true
        defer {
            isStreaming = false
            streamText = ""
            filteredStreamText = ""
            updateTokenHint()
            activeStreamingThreadID = nil
            state.markModelUsed()
        }

        let startTime = Date()
        
        do {
            guard let modelURL = state.findModelURL(for: modelId) else {
                presentError("Model '\(modelId)' not found. Please check Settings.")
                return
            }
            if !state.isModelLoaded || state.currentModelURL != modelURL {
                

                
                let validation = ModelValidator.validate(at: modelURL)
                if !validation.isValid {
                    presentError("Model validation failed:\n\n\(ModelValidator.errorMessage(from: validation))")
                    return
                }
            }
            
            let desiredConfig = state.getCurrentConfig(for: modelId)
            var config = state.thread(with: threadId)?.config ?? desiredConfig
            if config != desiredConfig {
                config = desiredConfig
            }
            config = state.clampedConfig(for: modelId, base: config)
            state.updateThread(threadId) { thread in
                thread.config = config
            }
            
            if state.currentModelURL != modelURL || !state.isModelLoaded {
                isLoadingModel = true
                defer { isLoadingModel = false }
                try await state.engine.loadModel(at: modelURL, config: config)
                state.currentModelURL = modelURL
                state.isModelLoaded = true
                state.currentEngineName = "MLX"
                state.markModelUsed()
            } else {
                state.engine.updateConfig(config)
            }
            
            // Ensure embedding model is loaded if RAG is enabled
            if state.thread(with: threadId)?.useDocumentContext == true {
                if !state.isEmbeddingModelLoaded {
                    try? await state.loadEmbeddingModel()
                }
            }
            
            let baseMessages = state.thread(with: threadId)?.messages ?? []
            let (messages, documentSources) = await messagesWithContext(from: baseMessages, question: trimmed, threadId: threadId)
            var accumulatedText = ""
            for await token in state.engine.stream(messages: messages) {
                accumulatedText += token
                let filtered = Self.filterSpecialTokens(accumulatedText)
                streamText = accumulatedText
                filteredStreamText = filtered
            }
            
        let responseTime = Date().timeIntervalSince(startTime)
        let finalText = filteredStreamText.isEmpty ? streamText : filteredStreamText
        let assistantMessage = Message(
            role: .assistant,
            text: finalText,
            referencedDocuments: documentSources.isEmpty ? nil : documentSources
        )
        state.updateThread(threadId) { thread in
            thread.messages.append(assistantMessage)
            thread.statistics.addMessage(assistantMessage, responseTime: responseTime)
        }
        let tokens = state.estimateTokens(from: finalText)
        await MainActor.run {
            state.lastTokensPerSecond = responseTime > 0 ? Double(tokens) / responseTime : nil
        }
        } catch {
            presentError(formatModelError(error))
        }
        
        updateTokenHint(activeConfig: state.selectedThread?.config)
        updateTokenHint(activeConfig: state.selectedThread?.config)
    }
    
    func loadSelectedModel() async {
        guard let modelId = state.selectedThread?.modelId, !modelId.isEmpty else { return }
        guard let modelURL = state.findModelURL(for: modelId) else {
            presentError("Model '\(modelId)' not found.")
            return
        }
        
        isLoadingModel = true
        defer { isLoadingModel = false }
        
        do {
            let config = state.clampedConfig(for: modelId, base: state.getCurrentConfig(for: modelId))
            try await state.engine.loadModel(at: modelURL, config: config)
            state.currentModelURL = modelURL
            state.isModelLoaded = true
            state.currentEngineName = "MLX"
            state.updateSelected { $0.config = config }
            state.markModelUsed()
        } catch {
            presentError(formatModelError(error))
        }
    }
    
    private func presentError(_ message: String) {
        errorMessage = message
        showError = true
    }
    
    private func formatModelError(_ error: Error) -> String {
        let errorDesc = error.localizedDescription
        let errorString = String(describing: error)
        
        if errorDesc.contains("safetensors") || errorString.contains("safetensors") ||
           errorDesc.contains("SafeTensors") || errorString.contains("SafeTensors") {
            return "Error loading model weights: \(errorDesc)\n\nThis usually means:\n• The model files are corrupted or incomplete\n• The safetensors format is incompatible\n• Try re-downloading the model or use a different model"
        } else if errorDesc.localizedCaseInsensitiveContains("memory") ||
                    errorDesc.localizedCaseInsensitiveContains("too large") ||
                    errorDesc.localizedCaseInsensitiveContains("allocation") {
            return "Model too large for device memory. Try a smaller model (under 1B parameters, 4-bit quantized). Recommended: Qwen1.5-0.5B-Chat-4bit or OpenELM-270M-Instruct"
        } else {
            return "Failed to load model: \(errorDesc)"
        }
    }
    
    private static func filterSpecialTokens(_ text: String) -> String {
        var filtered = text
        let inlinePatterns = [
            "<think>", "</think>",
            "<reasoning>", "</reasoning>",
            "<|think|>", "</|think|>",
            "<|reasoning|>", "</|reasoning|>",
            "<|redacted_reasoning|>", "</|redacted_reasoning|>",
            "```thinking", "```reasoning", "```thought"
        ]
        
        for pattern in inlinePatterns {
            let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
            let range = NSRange(location: 0, length: filtered.utf16.count)
            filtered = regex?.stringByReplacingMatches(in: filtered, options: [], range: range, withTemplate: "") ?? filtered
        }
        
        let blockPatterns = [
            "(?s)<think>.*?</think>",
            "(?s)<reasoning>.*?</reasoning>",
            "(?s)<\\|think\\|>.*?</\\|think\\|>",
            "(?s)<\\|reasoning\\|>.*?</\\|reasoning\\|>",
            "(?s)<\\|redacted_reasoning\\|>.*?</\\|redacted_reasoning\\|>"
        ]
        
        for pattern in blockPatterns {
            let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let range = NSRange(location: 0, length: filtered.utf16.count)
            filtered = regex?.stringByReplacingMatches(in: filtered, options: [], range: range, withTemplate: "") ?? filtered
        }
        
        // Remove stray end_of_turn tokens emitted by some models
        let endTokenPattern = "(?i)(end_of_turn)+"
        if let regex = try? NSRegularExpression(pattern: endTokenPattern, options: []) {
            let range = NSRange(location: 0, length: filtered.utf16.count)
            filtered = regex.stringByReplacingMatches(in: filtered, options: [], range: range, withTemplate: " ")
        }
        filtered = filtered.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
        
        return filtered
    }
    
    private func updateTokenHint(activeConfig: InferenceConfig? = nil) {
        let config = activeConfig ?? state.selectedThread?.config ?? state.getCurrentConfig(for: state.selectedThread?.modelId ?? "")
        currentTokenHint = "Max \(config.maxTokens) tokens"
    }
    
    func refreshTokenHint(for modelId: String?) {
        let config = state.getCurrentConfig(for: modelId ?? state.selectedThread?.modelId ?? "")
        updateTokenHint(activeConfig: config)
    }
    
    func stopStreaming() {
        guard isStreaming else { return }
        Task {
            await state.engine.cancel()
        }
    }
    
    private func messagesWithContext(from messages: [Message], question: String, threadId: UUID) async -> ([Message], [String]) {
        guard let thread = state.thread(with: threadId) else {
            return (messages, [])
        }
        let (contextMessage, sources) = await makeDocumentContextMessage(for: question, thread: thread)
        guard let contextMessage else {
            return (messages, [])
        }
        var updated = messages
        let insertIndex = max(0, updated.count - 1)
        updated.insert(contextMessage, at: insertIndex)
        return (updated, sources)
    }
    
    private func makeDocumentContextMessage(for question: String, thread: ChatThread) async -> (Message?, [String]) {
        guard thread.useDocumentContext else { return (nil, []) }
        let chunks = await relevantChunks(for: question, thread: thread)
        print("RAG: Retrieved \(chunks.count) chunks for question: \(question.prefix(20))...")
        guard !chunks.isEmpty else { return (nil, []) }
        let contextText = buildDocumentContextText(from: chunks)
        let sources = uniqueDocumentTitles(for: chunks)
        return (Message(role: .system, text: contextText), sources)
    }
    
    private func buildDocumentContextText(from chunks: [DocumentChunk]) -> String {
        var builder = """
        You are analyzing the user's personal documents. Be respectful and ground every answer in the excerpts below.
        
        ==== BEGIN USER DOCUMENT EXCERPTS ====
        """
        for chunk in chunks {
            let title = state.document(for: chunk.documentID)?.title ?? "Document \(chunk.documentID.uuidString.prefix(4))"
            builder += "\n<File: \(title) — chunk #\(chunk.index)>\n\(chunk.text)\n---"
        }
        builder += "\n==== END USER DOCUMENT EXCERPTS ====\nUse only this information when answering. If the answer is not present, say so."
        return builder
    }
    
    private func relevantChunks(for question: String, thread: ChatThread) async -> [DocumentChunk] {
        if thread.workspaceIDs.isEmpty {
            return await state.relevantDocumentChunks(for: question, topK: 12)
        }
        let chunks = await state.relevantDocumentChunks(
            for: question,
            topK: 30,
            workspaceFilter: Set(thread.workspaceIDs)
        )
        return Array(chunks.prefix(12))
    }
    
    private func uniqueDocumentTitles(for chunks: [DocumentChunk]) -> [String] {
        var seen: Set<UUID> = []
        var titles: [String] = []
        for chunk in chunks {
            let identifier = chunk.documentID
            guard !seen.contains(identifier) else { continue }
            seen.insert(identifier)
            if let title = state.document(for: identifier)?.title {
                titles.append(title)
            }
        }
        return titles
    }
}
