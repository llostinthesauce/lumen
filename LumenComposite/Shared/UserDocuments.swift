import Foundation

public enum UserDocumentKind: String, Codable, CaseIterable {
    case journal
    case note
    case generic
    case code
}

public struct UserDocument: Identifiable, Codable, Equatable {
    public let id: UUID
    public var title: String
    public var kind: UserDocumentKind
    public var fileURL: URL
    public var createdAt: Date
    public var updatedAt: Date
    public var preview: String?
    public var wordCount: Int?
    public var workspaceID: UUID?
    
    public init(
        id: UUID = UUID(),
        title: String,
        kind: UserDocumentKind = .generic,
        fileURL: URL,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        preview: String? = nil,
        wordCount: Int? = nil,
        workspaceID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.fileURL = fileURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.preview = preview
        self.wordCount = wordCount
        self.workspaceID = workspaceID
    }
}

public struct DocumentChunk: Identifiable, Codable, Equatable {
    public let id: UUID
    public let documentID: UUID
    public let index: Int
    public let text: String
    
    public init(
        id: UUID = UUID(),
        documentID: UUID,
        index: Int,
        text: String
    ) {
        self.id = id
        self.documentID = documentID
        self.index = index
        self.text = text
    }
}
