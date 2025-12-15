import Foundation
import Network
import Combine

final class APIServer: ObservableObject {
    private var listener: NWListener?
    private let port: NWEndpoint.Port
    private let state: AppState
    private let modelLoadLock = ModelLoadLock()
    private let requestLimiter = RequestLimiter(maxConcurrent: 4)
    private let maxBodyBytes = 4 * 1024 * 1024 // 4 MB guard
    private let readTimeout: TimeInterval = 10
    
    init(port: UInt16 = 1234, state: AppState) {
        self.port = NWEndpoint.Port(integerLiteral: port)
        self.state = state
    }
    
    func start() throws {
        let listener = try NWListener(using: .tcp, on: port)
        
        listener.stateUpdateHandler = { newState in
            Task { @MainActor in
                switch newState {
                case .ready:
                    ServerState.shared.log("Server ready on port \(self.port)")
                    ServerState.shared.isRunning = true
                case .failed(let error):
                    ServerState.shared.log("Server failed: \(error)")
                    ServerState.shared.isRunning = false
                default:
                    break
                }
            }
        }
        
        listener.newConnectionHandler = { [weak self] newConnection in
            guard let self else { return }
            // Reject non-local connections
            if !self.isLocalConnection(newConnection) {
                Task { @MainActor in
                    ServerState.shared.log("Rejected non-local connection")
                }
                newConnection.cancel()
                return
            }
            self.handleConnection(newConnection)
        }
        
        listener.start(queue: .global(qos: .userInitiated))
        self.listener = listener
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global())
        readRequest(from: connection, buffer: Data(), deadline: Date().addingTimeInterval(readTimeout))
    }

    /// Read an HTTP request, handling fragmentation, Content-Length bodies, size limits, and a simple timeout.
    private func readRequest(from connection: NWConnection, buffer: Data, deadline: Date) {
        if Date() > deadline {
            connection.cancel()
            return
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                connection.cancel()
                Task { @MainActor in
                    ServerState.shared.log("Connection error: \(error)")
                }
                return
            }
            
            var newBuffer = buffer
            if let data {
                if newBuffer.count + data.count > self.maxBodyBytes {
                    self.sendResponse(self.errorResponse("Request too large", status: .payloadTooLarge), connection: connection)
                    connection.cancel()
                    return
                }
                newBuffer.append(data)
            }
            
            if let request = HTTPRequest(buffer: newBuffer, maxBody: self.maxBodyBytes) {
                Task {
                    await self.requestLimiter.withPermit {
                        if let response = await self.route(request: request, connection: connection) {
                            self.sendResponse(response, connection: connection)
                        }
                    }
                }
                return
            }
            
            if isComplete {
                connection.cancel()
                return
            }
            
            self.readRequest(from: connection, buffer: newBuffer, deadline: deadline)
        }
    }
    
    private func route(request: HTTPRequest, connection: NWConnection) async -> HTTPResponse? {
        await MainActor.run {
            ServerState.shared.log("\(request.method) \(request.path)")
        }
        
        switch (request.method, request.path) {
        case ("GET", "/v1/models"):
            return await handleListModels()
        case ("POST", "/v1/chat/completions"):
            let shouldStream = request.jsonFlag("stream") ?? false
            if shouldStream {
                await streamChatCompletions(body: request.bodyString, connection: connection)
                return nil
            } else {
                return await handleChatCompletions(body: request.bodyString)
            }
        case ("OPTIONS", _):
            return corsResponse()
        default:
            return notFoundResponse()
        }
    }
    
    private func sendResponse(_ response: HTTPResponse, connection: NWConnection) {
        connection.send(content: response.rawValue.data(using: .utf8), completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }
    
    // MARK: - Handlers
    
    private func handleListModels() async -> HTTPResponse {
        let models: [String] = await MainActor.run {
            state.listModelFolders()
        }
        
        let jsonModels = models.map { id in
            [
                "id": id,
                "object": "model",
                "created": Int(Date().timeIntervalSince1970),
                "owned_by": "user"
            ] as [String : Any]
        }
        
        let response: [String: Any] = [
            "object": "list",
            "data": jsonModels
        ]
        
        return jsonResponse(response)
    }
    
    private func handleChatCompletions(body: String) async -> HTTPResponse {
        guard
            let data = body.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let messagesJson = json["messages"] as? [[String: Any]]
        else {
            return errorResponse("Invalid JSON body")
        }
        
        let modelId = json["model"] as? String ?? ""
        guard !modelId.isEmpty else { return errorResponse("Missing model id") }
        
        let chatMessages: [Message]
        do {
            chatMessages = try parseChatMessages(messagesJson)
        } catch {
            return errorResponse(error.localizedDescription)
        }
        if chatMessages.isEmpty { return errorResponse("No messages provided") }
        
        // Ensure model is loaded
        do {
            try await ensureModelLoaded(modelId: modelId)
        } catch {
            return errorResponse(error.localizedDescription)
        }
        
        // Generate completion
        var generatedText = ""
        let stream = await MainActor.run {
            state.engine.stream(messages: chatMessages)
        }
        
        for await token in stream {
            generatedText += token
        }
        await MainActor.run { state.markModelUsed() }
        
        let usage = approximateUsage(messages: chatMessages, completion: generatedText)
        let response: [String: Any] = [
            "id": "chatcmpl-\(UUID().uuidString)",
            "object": "chat.completion",
            "created": Int(Date().timeIntervalSince1970),
            "model": modelId,
            "choices": [
                [
                    "index": 0,
                    "message": [
                        "role": "assistant",
                        "content": generatedText
                    ],
                    "finish_reason": "stop"
                ]
            ],
            "usage": usage
        ]
        
        return jsonResponse(response)
    }
    
    private func streamChatCompletions(body: String, connection: NWConnection) async {
        guard
            let data = body.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let messagesJson = json["messages"] as? [[String: Any]]
        else {
            sendResponse(errorResponse("Invalid JSON body"), connection: connection)
            return
        }
        
        let modelId = json["model"] as? String ?? ""
        guard !modelId.isEmpty else { sendResponse(errorResponse("Missing model id"), connection: connection); return }
        
        let chatMessages: [Message]
        do {
            chatMessages = try parseChatMessages(messagesJson)
        } catch {
            sendResponse(errorResponse(error.localizedDescription), connection: connection)
            return
        }
        if chatMessages.isEmpty {
            sendResponse(errorResponse("No messages provided"), connection: connection)
            return
        }
        
        do {
            try await ensureModelLoaded(modelId: modelId)
        } catch {
            sendResponse(errorResponse(error.localizedDescription), connection: connection)
            return
        }
        
        // Send SSE headers
        let header = """
        HTTP/1.1 200 OK\r
        Content-Type: text/event-stream\r
        Cache-Control: no-cache\r
        Connection: keep-alive\r
        Access-Control-Allow-Origin: *\r
\r
"""
        connection.send(content: header.data(using: .utf8), completion: .contentProcessed({ _ in }))
        
        let stream = await MainActor.run {
            state.engine.stream(messages: chatMessages)
        }
        
        let chunkId = "chatcmpl-\(UUID().uuidString)"
        var index = 0
        var lastHeartbeat = Date()
        for await token in stream {
            index += 1
            let chunk: [String: Any] = [
                "id": chunkId,
                "object": "chat.completion.chunk",
                "created": Int(Date().timeIntervalSince1970),
                "model": modelId,
                "choices": [
                    [
                        "index": 0,
                        "delta": [
                            "content": token
                        ],
                        "finish_reason": NSNull()
                    ]
                ]
            ]
            if let jsonData = try? JSONSerialization.data(withJSONObject: chunk),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                let payload = "data: \(jsonString)\r\n\r\n"
                connection.send(content: payload.data(using: .utf8), completion: .contentProcessed({ _ in }))
            }
            // Heartbeat every 5 seconds to keep clients alive
            if Date().timeIntervalSince(lastHeartbeat) > 5 {
                let hb = ": ping\r\n\r\n"
                connection.send(content: hb.data(using: .utf8), completion: .contentProcessed({ _ in }))
                lastHeartbeat = Date()
            }
        }
        await MainActor.run { state.markModelUsed() }
        
        let doneChunk: [String: Any] = [
            "id": chunkId,
            "object": "chat.completion.chunk",
            "created": Int(Date().timeIntervalSince1970),
            "model": modelId,
            "choices": [
                [
                    "index": 0,
                    "delta": [:],
                    "finish_reason": "stop"
                ]
            ]
        ]
        if let jsonData = try? JSONSerialization.data(withJSONObject: doneChunk),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            let payload = "data: \(jsonString)\r\n\r\n"
            connection.send(content: payload.data(using: .utf8), completion: .contentProcessed({ _ in }))
        }
        let done = "data: [DONE]\r\n\r\n"
        connection.send(content: done.data(using: .utf8), completion: .contentProcessed({ _ in
            connection.cancel()
        }))
    }
    
    // MARK: - Helpers
    
    private func ensureModelLoaded(modelId: String) async throws {
        guard let modelURL = await MainActor.run(body: { state.findModelURL(for: modelId) }) else {
            throw NSError(domain: "APIServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model '\(modelId)' not found"])
        }
        
        try await modelLoadLock.withLock {
            let isAlreadyLoaded = await MainActor.run(body: {
                self.state.isModelLoaded && self.state.currentModelURL == modelURL
            })
            if isAlreadyLoaded {
                await MainActor.run { self.state.markModelUsed() }
                return
            }
            
            let config = await MainActor.run {
                self.state.clampedConfig(for: modelId, base: self.state.getCurrentConfig(for: modelId))
            }
            
            try await self.state.engine.loadModel(at: modelURL, config: config)
            await MainActor.run {
                self.state.currentModelURL = modelURL
                self.state.isModelLoaded = true
                self.state.currentEngineName = "MLX"
                self.state.markModelUsed()
            }
        }
    }
    
    /// Only allow loopback connections.
    private func isLocalConnection(_ connection: NWConnection) -> Bool {
        if case let .hostPort(host, _) = connection.endpoint {
            switch host {
            case .ipv4(let addr):
                return addr == .loopback
            case .ipv6(let addr):
                return addr == .loopback
            case .name(let name, _):
                return name == "localhost"
            @unknown default:
                return false
            }
        }
        return false
    }
    
    private func jsonResponse(_ json: [String: Any]) -> HTTPResponse {
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let jsonString = String(data: data, encoding: .utf8) else {
            return errorResponse("Internal Server Error")
        }
        
        return HTTPResponse(
            status: .ok,
            headers: [
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*",
                "Content-Length": "\(data.count)"
            ],
            body: jsonString
        )
    }
    
    private func corsResponse() -> HTTPResponse {
        HTTPResponse(
            status: .ok,
            headers: [
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
                "Access-Control-Allow-Headers": "Content-Type, Authorization, Accept, OpenAI-Beta",
                "Content-Length": "0"
            ],
            body: ""
        )
    }
    
    private func notFoundResponse() -> HTTPResponse {
        HTTPResponse(
            status: .notFound,
            headers: [
                "Content-Length": "0"
            ],
            body: ""
        )
    }
    
    private func errorResponse(_ message: String, status: HTTPStatus = .badRequest) -> HTTPResponse {
        let json = ["error": ["message": message, "type": "invalid_request_error"]]
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let jsonString = String(data: data, encoding: .utf8) else {
            return HTTPResponse(status: status)
        }
        return HTTPResponse(
            status: status,
            headers: [
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*",
                "Content-Length": "\(data.count)"
            ],
            body: jsonString
        )
    }
    
    private func approximateUsage(messages: [Message], completion: String) -> [String: Int] {
        let promptChars = messages.reduce(0) { $0 + $1.text.count }
        let completionChars = completion.count
        let promptTokens = max(1, promptChars / 4)
        let completionTokens = max(1, completionChars / 4)
        return [
            "prompt_tokens": promptTokens,
            "completion_tokens": completionTokens,
            "total_tokens": promptTokens + completionTokens
        ]
    }
    
    /// Parse OpenAI-style chat messages, accepting either string content or content arrays with text items.
    private func parseChatMessages(_ messagesJson: [[String: Any]]) throws -> [Message] {
        var chatMessages: [Message] = []
        for msg in messagesJson {
            guard let roleStr = msg["role"] as? String,
                  let role = Message.Role(rawValue: roleStr) else { continue }
            if let content = msg["content"] as? String {
                chatMessages.append(Message(role: role, text: content))
                continue
            }
            if let parts = msg["content"] as? [[String: Any]] {
                let text = parts.compactMap { part -> String? in
                    guard let type = part["type"] as? String else { return nil }
                    if type == "image_url" {
                        return nil
                    }
                    if type == "text" {
                        if let textValue = part["text"] as? String { return textValue }
                        if let textObj = part["text"] as? [String: Any],
                           let value = textObj["value"] as? String { return value }
                    }
                    return nil
                }.joined(separator: "")
                if !text.isEmpty {
                    chatMessages.append(Message(role: role, text: text))
                }
                continue
            }
        }
        // Reject unsupported content types (e.g., images/tools) for this text-only build.
        let hasUnsupported = messagesJson.contains { msg in
            guard let parts = msg["content"] as? [[String: Any]] else { return false }
            return parts.contains { ($0["type"] as? String) == "image_url" }
        }
        if hasUnsupported {
            throw NSError(domain: "APIServer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Only text content is supported for this server. Remove image or tool content."])
        }
        return chatMessages
    }
}

// Minimal HTTP parsing helpers
private struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
    
    var bodyString: String { String(data: body, encoding: .utf8) ?? "" }
    
    init?(buffer: Data, maxBody: Int) {
        guard let headerEndRange = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            return nil // need more data
        }
        let headerData = buffer.subdata(in: 0..<headerEndRange.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }
        var lines = headerString.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first else { return nil }
        lines.removeFirst()
        let tokens = requestLine.split(separator: " ")
        guard tokens.count >= 2 else { return nil }
        method = String(tokens[0])
        path = String(tokens[1])
        
        var headers: [String: String] = [:]
        for line in lines {
            let parts = line.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 {
                headers[parts[0].lowercased()] = parts[1]
            }
        }
        self.headers = headers
        
        let bodyStart = headerEndRange.upperBound
        let bodyData = buffer.subdata(in: bodyStart..<buffer.count)
        if let lengthHeader = headers["content-length"], let expectedLength = Int(lengthHeader) {
            if expectedLength > maxBody { return nil }
            if expectedLength > bodyData.count { return nil } // wait for more body
            self.body = bodyData.prefix(expectedLength)
        } else {
            // No content-length: treat as no body for now
            self.body = Data()
        }
    }
    
    func jsonFlag(_ key: String) -> Bool? {
        guard
            let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
            let value = json[key] as? Bool
        else { return nil }
        return value
    }
}

private struct HTTPResponse {
    let status: HTTPStatus
    let headers: [String: String]
    let body: String
    
    var rawValue: String {
        var lines: [String] = []
        lines.append("HTTP/1.1 \(status.rawValue)")
        headers.forEach { key, value in
            lines.append("\(key): \(value)")
        }
        lines.append("")
        lines.append(body)
        return lines.joined(separator: "\r\n")
    }
    
    init(status: HTTPStatus, headers: [String: String] = [:], body: String = "") {
        self.status = status
        self.headers = headers
        self.body = body
    }
}

private enum HTTPStatus: String {
    case ok = "200 OK"
    case badRequest = "400 Bad Request"
    case payloadTooLarge = "413 Payload Too Large"
    case tooManyRequests = "429 Too Many Requests"
    case notFound = "404 Not Found"
    case internalError = "500 Internal Server Error"
}

/// Simple async lock to serialize model loading.
private actor ModelLoadLock {
    private var isLoading = false
    
    func withLock<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        while isLoading {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        isLoading = true
        defer { isLoading = false }
        return try await operation()
    }
}

/// Simple concurrency limiter to avoid excessive simultaneous requests.
private actor RequestLimiter {
    private let maxConcurrent: Int
    private var current: Int = 0
    
    init(maxConcurrent: Int) {
        self.maxConcurrent = maxConcurrent
    }
    
    func withPermit(_ operation: @escaping () async -> Void) async {
        while current >= maxConcurrent {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        current += 1
        defer { current = max(0, current - 1) }
        await operation()
    }
}
