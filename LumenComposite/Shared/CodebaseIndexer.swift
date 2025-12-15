import Foundation

public final class CodebaseIndexer {
    private let documentIndexer: DocumentIndexer
    private let documentLibrary: DocumentLibrary
    private let fileManager: FileManager
    
    public init(documentIndexer: DocumentIndexer, documentLibrary: DocumentLibrary, fileManager: FileManager = .default) {
        self.documentIndexer = documentIndexer
        self.documentLibrary = documentLibrary
        self.fileManager = fileManager
    }
    
    /// Recursively indexes all valid code files in the workspace
    /// Returns a summary of what was indexed and skipped
    public func indexWorkspace(_ workspace: CodeWorkspace, documentMap: [URL: UserDocument]? = nil) async throws -> DocumentIndexer.IndexingResult {
        let rootURL = workspace.rootURL
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isHiddenKey]
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
        
        // Verify workspace root exists
        guard fileManager.fileExists(atPath: rootURL.path) else {
            throw NSError(domain: "CodebaseIndexer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Workspace root not found: \(rootURL.path)"])
        }
        
        // Create enumerator
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: resourceKeys,
            options: options
        ) else {
            throw NSError(domain: "CodebaseIndexer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create enumerator for \(rootURL.path)"])
        }
        
        var filesToIndex: [URL] = []
        
        // Collect files first to avoid blocking the enumerator with async work
        for case let fileURL as URL in enumerator {
            // Check for ignore patterns
            if shouldIgnore(fileURL, root: rootURL, patterns: workspace.effectiveIgnorePatterns()) {
                if let isDir = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDir {
                    enumerator.skipDescendants()
                }
                continue
            }
            
            // Check if it's a file we want to index
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isHiddenKey]),
               resourceValues.isRegularFile == true,
               resourceValues.isHidden != true {
                
                // Check extension if languages are specified
                if !workspace.languages.isEmpty {
                    let ext = fileURL.pathExtension.lowercased()
                    if !workspace.languages.contains(where: { $0.lowercased() == ext }) {
                        continue
                    }
                }
                
                filesToIndex.append(fileURL)
            }
        }
        
        // Index files and collect results
        var indexed = 0
        var skipped = 0
        var skipReasons: [String: Int] = [:]
        var totalChunks = 0
        
        for fileURL in filesToIndex {
            // Check if file still exists (could be deleted during indexing)
            guard fileManager.fileExists(atPath: fileURL.path) else {
                skipped += 1
                skipReasons["deleted", default: 0] += 1
                continue
            }
            
            let document = documentMap?[fileURL] ?? documentLibrary.document(forFileURL: fileURL)
            
            do {
                let chunks = try await indexFile(at: fileURL, workspace: workspace, document: document)
                indexed += 1
                totalChunks += chunks
            } catch let error as DocumentIndexer.IndexingError {
                skipped += 1
                let reason: String
                switch error {
                case .fileTooLarge:
                    reason = "too large"
                case .binaryContent:
                    reason = "binary"
                case .emptyContent:
                    reason = "empty"
                case .invalidContent:
                    reason = "invalid"
                }
                skipReasons[reason, default: 0] += 1
            } catch {
                // Other errors (file read, encoding, etc.)
                skipped += 1
                skipReasons["read error", default: 0] += 1
            }
        }
        
        return DocumentIndexer.IndexingResult(
            indexed: indexed,
            skipped: skipped,
            skipReasons: skipReasons,
            chunksCreated: totalChunks
        )
    }
    
    private func indexFile(at url: URL, workspace: CodeWorkspace, document: UserDocument?) async throws -> Int {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            throw DocumentIndexer.IndexingError.invalidContent(reason: "Failed to read as UTF-8")
        }
        
        let relativePath = url.path.replacingOccurrences(of: workspace.rootURL.path, with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        var metadata: [String: Any] = [
            "filePath": relativePath,
            "workspaceID": workspace.id.uuidString,
            "language": url.pathExtension,
            "kind": "code"
        ]
        if let document = document {
            metadata["documentID"] = document.id.uuidString
            metadata["title"] = document.title
        }
        
        // Use the file path as the source ID for easy updates/deletions
        let sourceID = "file://\(workspace.id.uuidString)/\(relativePath)"
        
        // DocumentIndexer now validates and throws specific errors
        try await documentIndexer.indexDocument(
            sourceID: sourceID,
            content: content,
            kind: .code,
            metadata: metadata
        )
        
        // Count chunks for reporting (approximate from content)
        let lineCount = content.components(separatedBy: .newlines).count
        let approxChunks = max(1, lineCount / 80)  // Rough estimate based on code chunk size
        return approxChunks
    }
    
    private func shouldIgnore(_ url: URL, root: URL, patterns: [String]) -> Bool {
        let path = url.path
        let relativePath = path.replacingOccurrences(of: root.path, with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        for pattern in patterns {
            // Simple glob-like matching
            // 1. Exact match (e.g. "node_modules")
            if relativePath == pattern || relativePath.hasPrefix(pattern + "/") {
                return true
            }
            
            // 2. Extension match (e.g. "*.o")
            if pattern.hasPrefix("*.") {
                let ext = String(pattern.dropFirst(2))
                if url.pathExtension == ext {
                    return true
                }
            }
            
            // 3. Directory match (e.g. ".git")
            if url.lastPathComponent == pattern {
                return true
            }
        }
        
        return false
    }
}
