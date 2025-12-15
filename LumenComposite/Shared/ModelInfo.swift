import Foundation

/// Information about a model
public struct ModelInfo {
    public let name: String
    public let format: ModelFormat
    public let url: URL
    public let hasTokenizer: Bool
    public let size: Int64? // Size in bytes
    
    public init(name: String, format: ModelFormat, url: URL, hasTokenizer: Bool, size: Int64? = nil) {
        self.name = name
        self.format = format
        self.url = url
        self.hasTokenizer = hasTokenizer
        self.size = size
    }
    
    /// Format size as human-readable string
    public var sizeString: String {
        guard let size = size else { return "Unknown size" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

/// Model information provider
public struct ModelInfoProvider {
    /// Get information about a model
    public static func getInfo(for modelId: String, modelsURL: URL) -> ModelInfo? {
        let fm = FileManager.default
        let documentsURL = modelsURL.appendingPathComponent(modelId, isDirectory: true)
        let bundledURL = ModelStorage.shared.bundledModelFolders()
            .first(where: { $0.lastPathComponent == modelId })
        
        func validURL(_ url: URL?) -> (url: URL, format: ModelFormat)? {
            guard let url = url else { return nil }
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return nil
            }
            let format = ModelFormatDetector.detectFormat(at: url)
            return format == .unknown ? nil : (url, format)
        }
        
        guard let resolved = validURL(documentsURL) ?? validURL(bundledURL) else {
            return nil
        }
        
        let modelURL = resolved.url
        let format = resolved.format
        
        // Check for tokenizer
        let hasTokenizer = checkTokenizer(at: modelURL)
        
        // Calculate size
        let size = calculateSize(at: modelURL)
        
        return ModelInfo(
            name: modelId,
            format: format,
            url: modelURL,
            hasTokenizer: hasTokenizer,
            size: size
        )
    }
    
    /// Check if tokenizer files exist
    private static func checkTokenizer(at url: URL) -> Bool {
        let fm = FileManager.default
        let tokenizerFiles = ["tokenizer.json", "tokenizer_config.json"]
        
        for fileName in tokenizerFiles {
            let tokenizerURL = url.appendingPathComponent(fileName)
            if fm.fileExists(atPath: tokenizerURL.path) {
                return true
            }
        }
        
        return false
    }
    
    /// Calculate total size of model directory
    private static func calculateSize(at url: URL) -> Int64 {
        let fm = FileManager.default
        var totalSize: Int64 = 0
        
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return 0
        }
        
        for case let fileURL as URL in enumerator {
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let fileSize = resourceValues.fileSize {
                totalSize += Int64(fileSize)
            }
        }
        
        return totalSize
    }
}




