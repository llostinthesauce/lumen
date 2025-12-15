import Foundation

/// Manages model storage locations and paths
final class ModelStorage {
    static let shared = ModelStorage()
    private init() {}
    private let bundledModelsFlagKey = "ModelStorage.bundledModelsInstalled"
    
    // MARK: - Paths
    
    /// Default models directory based on platform
    var defaultModelsURL: URL {
        #if os(macOS)
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents
            .appendingPathComponent("LumenComposite", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
        #else
        // iOS: Use Documents directory (sandboxed, App Store compliant)
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("Models", isDirectory: true)
        #endif
    }
    
    /// User-configurable custom model path (stored in UserDefaults)
    private let customModelPathKey = "com.conyshanks.lumenLLM.LumenComposite.customModelPath"
    
    /// The current models directory URL (custom path if set, otherwise default)
    var modelsURL: URL {
        if let custom = customModelPath {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return defaultModelsURL
    }
    
    /// Get the custom model path if set
    var customModelPath: String? {
        let path = UserDefaults.standard.string(forKey: customModelPathKey)
        return path?.isEmpty == false ? path : nil
    }
    
    /// Set a custom model path (nil to reset to default)
    func setCustomModelPath(_ path: String?) {
        if let path = path, !path.isEmpty {
            UserDefaults.standard.set(path, forKey: customModelPathKey)
        } else {
            UserDefaults.standard.removeObject(forKey: customModelPathKey)
        }
    }
    
    /// All candidate root directories that may contain user models.
    /// Includes custom path, default Application Support folder, and legacy Documents location.
    func candidateModelRootURLs() -> [URL] {
        var roots: [URL] = []
        if let custom = customModelPath {
            roots.append(URL(fileURLWithPath: custom, isDirectory: true))
        }
        let defaultRoot = defaultModelsURL
        if !roots.contains(where: { $0.standardizedFileURL == defaultRoot.standardizedFileURL }) {
            roots.append(defaultRoot)
        }
        return roots
    }
    
    // MARK: - Setup
    
    /// Ensure the models directory exists (creates it if needed)
    func ensureModelsDirExists() {
        let fm = FileManager.default
        let url = modelsURL
        
        // Only create if it doesn't exist (don't create custom paths - user should create those)
        if !fm.fileExists(atPath: url.path) {
            // Only auto-create the default path, not custom paths
            if customModelPath == nil {
                try? fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
            }
        }
    }
    
    /// Copy bundled models into the writable models directory if they're missing.
    func installBundledModelsIfNeeded() {
        #if os(iOS)
        guard customModelPath == nil else { return }
        ensureModelsDirExists()
        let fm = FileManager.default
        let bundledFolders = bundledModelFolders()
        
        var installedAnything = false
        for item in bundledFolders {
            guard fm.fileExists(atPath: item.path) else {
                continue
            }
            
            let destination = modelsURL.appendingPathComponent(item.lastPathComponent, isDirectory: true)
            if fm.fileExists(atPath: destination.path) {
                continue
            }
            
            do {
                try fm.copyItem(at: item, to: destination)
                installedAnything = true
            } catch {
                print("Failed to copy bundled model \(item.lastPathComponent): \(error.localizedDescription)")
            }
        }
        
        if installedAnything {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: bundledModelsFlagKey)
        }
        #endif
    }
    
    /// Enumerate bundled model directories regardless of on-disk folder names.
    func bundledModelFolders() -> [URL] {
        guard let base = Bundle.main.resourceURL else { return [] }
        let fm = FileManager.default
        var roots: [URL] = []
        for name in ["Models", "BundledModels"] {
            let candidate = base.appendingPathComponent(name, isDirectory: true)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
                roots.append(candidate)
            }
        }
        if roots.isEmpty {
            roots = [base]
        }
        
        var folders: [URL] = []
        for root in roots {
            collectModelFolders(at: root, depth: 0, into: &folders)
        }
        return folders
    }

    /// Returns true if either the bundled resources or any user model folder contains the given directory.
    func hasModelDirectory(named name: String) -> Bool {
        if bundledModelFolders().contains(where: { $0.lastPathComponent == name }) {
            return true
        }
        let fm = FileManager.default
        for root in candidateModelRootURLs() {
            let candidate = root.appendingPathComponent(name, isDirectory: true)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
                return true
            }
        }
        return false
    }

    private func collectModelFolders(at directory: URL, depth: Int, maxDepth: Int = 2, into folders: inout [URL]) {
        guard depth <= maxDepth else { return }
        guard let items = try? FileManager.default.contentsOfDirectory(
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
            let name = item.lastPathComponent.lowercased()
            // Skip common subfolders of diffusion pipelines so we only surface the root model directory.
            if ["unet", "vae", "text_encoder", "text_encoder_2", "tokenizer", "tokenizer_2", "scheduler"].contains(name) {
                continue
            }
            if isLikelyModelDirectory(item) {
                folders.append(item)
            } else if depth < maxDepth {
                collectModelFolders(at: item, depth: depth + 1, maxDepth: maxDepth, into: &folders)
            }
        }
    }
    
    private func isLikelyModelDirectory(_ url: URL) -> Bool {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return false
        }
        let lowerNames = contents.map { $0.lastPathComponent.lowercased() }
        let hasConfig = lowerNames.contains("config.json")
        let hasTokenizer = lowerNames.contains("tokenizer.json") || lowerNames.contains("tokenizer_config.json")
        let hasWeights = contents.contains { $0.pathExtension.lowercased() == "safetensors" || $0.lastPathComponent.lowercased() == "model.safetensors.index.json" }

        if hasConfig && hasWeights && hasTokenizer {
            return true
        }
        
        // Fallback to format detection (MLX-only)
        let format = ModelFormatDetector.detectFormat(at: url)
        return format == .mlx
    }
    
    // MARK: - Model Import
    
    /// Import model files/folders into the models directory
    func importItems(urls: [URL]) throws {
        ensureModelsDirExists()
        let fm = FileManager.default
        let destination = modelsURL
        var errors: [String] = []
        
        for url in urls {
            // iOS: Start accessing security-scoped resource
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
                errors.append("\(url.lastPathComponent): File not found")
                continue
            }
            
            do {
                let dest = destination.appendingPathComponent(url.lastPathComponent, isDirectory: isDir.boolValue)
                
                // Remove existing item if it exists
                if fm.fileExists(atPath: dest.path) {
                    try? fm.removeItem(at: dest)
                }
                
                try fm.copyItem(at: url, to: dest)
            } catch {
                errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        
        if !errors.isEmpty {
            throw NSError(domain: "ModelStorage", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Import failed: \(errors.joined(separator: "; "))"
            ])
        }
    }
    
    /// Delete a model directory by name from the first matching root.
    func deleteModel(named name: String) throws {
        let fm = FileManager.default
        for root in candidateModelRootURLs() {
            let target = root.appendingPathComponent(name, isDirectory: true)
            if fm.fileExists(atPath: target.path) {
                try fm.removeItem(at: target)
                return
            }
        }
        throw NSError(domain: "ModelStorage", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "Model '\(name)' not found."
        ])
    }
}
