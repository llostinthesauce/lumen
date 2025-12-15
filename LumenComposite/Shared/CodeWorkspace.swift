import Foundation

public struct CodeWorkspace: Identifiable, Codable, Equatable {
    public let id: UUID
    public var name: String
    public var rootURL: URL
    public var createdAt: Date
    public var updatedAt: Date
    public var languages: [String]
    public var ignorePatterns: [String]
    public var isWatching: Bool
    public var bookmarkData: Data?
    
    public init(
        id: UUID = UUID(),
        name: String,
        rootURL: URL,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        languages: [String] = [],
        ignorePatterns: [String] = [".git", "build", "DerivedData", "node_modules"],
        isWatching: Bool = false,
        bookmarkData: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.rootURL = rootURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.languages = languages
        self.ignorePatterns = ignorePatterns
        self.isWatching = isWatching
        self.bookmarkData = bookmarkData
    }

    
    public func effectiveIgnorePatterns() -> [String] {
        // Start with default patterns
        var patterns = [".git", "build", "DerivedData", "node_modules", ".DS_Store"]
        // Add user-defined patterns
        patterns.append(contentsOf: ignorePatterns)
        return Array(Set(patterns)) // Deduplicate
    }
    
    // Security-scoped access methods
    #if os(macOS)
    public func withSecurityScopedAccess<T>(perform block: (URL) throws -> T) rethrows -> T {
        var accessed = false
        var securedURL: URL = rootURL
        if let bookmarkData {
            var stale = false
            if let resolved = try? URL(resolvingBookmarkData: bookmarkData, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) {
                securedURL = resolved
                accessed = securedURL.startAccessingSecurityScopedResource()
            }
        }
        defer {
            if accessed {
                securedURL.stopAccessingSecurityScopedResource()
            }
        }
        return try block(securedURL)
    }
    
    public func scopedURLHandle() -> (url: URL, revoke: () -> Void) {
        var accessed = false
        var securedURL: URL = rootURL
        if let bookmarkData {
            var stale = false
            if let resolved = try? URL(resolvingBookmarkData: bookmarkData, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) {
                securedURL = resolved
                accessed = securedURL.startAccessingSecurityScopedResource()
            }
        }
        let revoke = {
            if accessed {
                securedURL.stopAccessingSecurityScopedResource()
            }
        }
        return (securedURL, revoke)
    }
    #else
    // iOS stub implementations - these should never be called since code workspace features are macOS-only
    public func withSecurityScopedAccess<T>(perform block: (URL) throws -> T) rethrows -> T {
        return try block(rootURL)
    }
    
    public func scopedURLHandle() -> (url: URL, revoke: () -> Void) {
        return (rootURL, {})
    }
    #endif
}
