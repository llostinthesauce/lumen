import Foundation

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
