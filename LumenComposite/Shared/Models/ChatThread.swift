import Foundation

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
