import Foundation

/// Model validation results
public struct ModelValidationResult {
    public let isValid: Bool
    public let format: ModelFormat
    public let issues: [String]
    public let warnings: [String]
    public let estimatedMemoryMB: Int?
    
    public init(isValid: Bool, format: ModelFormat, issues: [String] = [], warnings: [String] = [], estimatedMemoryMB: Int? = nil) {
        self.isValid = isValid
        self.format = format
        self.issues = issues
        self.warnings = warnings
        self.estimatedMemoryMB = estimatedMemoryMB
    }
    
    public var hasWarnings: Bool {
        !warnings.isEmpty
    }
}

/// Model validator
public struct ModelValidator {
    /// Check if an embedding model exists and is valid
    public static func validateEmbeddingModel(modelId: String) -> ModelValidationResult {
        // Check bundled models first
        if let bundledURL = ModelStorage.shared.bundledModelFolders()
            .first(where: { $0.lastPathComponent == modelId }) {
            return validate(at: bundledURL)
        }
        
        // Check user models directory
        let modelsURL = ModelStorage.shared.modelsURL.appendingPathComponent(modelId, isDirectory: true)
        if FileManager.default.fileExists(atPath: modelsURL.path) {
            return validate(at: modelsURL)
        }
        
        // Model not found
        return ModelValidationResult(
            isValid: false,
            format: .unknown,
            issues: ["Embedding model '\(modelId)' not found in bundled or user models directories"]
        )
    }
    
    /// Validate a model directory
    public static func validate(at url: URL) -> ModelValidationResult {
        let fm = FileManager.default
        var issues: [String] = []
        var warnings: [String] = []
        var estimatedMemoryMB: Int? = nil
        
        // Check if directory exists
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return ModelValidationResult(
                isValid: false,
                format: .unknown,
                issues: ["Model directory does not exist"]
            )
        }
        
        // Detect format
        let format = ModelFormatDetector.detectFormat(at: url)
        
        if format != .mlx {
            return ModelValidationResult(
                isValid: false,
                format: format,
                issues: ["Unsupported model format. Lumen now only supports MLX checkpoints (config.json + safetensors)."]
            )
        }
        
        // Estimate memory requirements
        estimatedMemoryMB = estimateMemoryRequirement(at: url, fileManager: fm)
        
        // Validate based on format
        return validateMLXModel(at: url, fileManager: fm, issues: &issues, warnings: &warnings, estimatedMemoryMB: estimatedMemoryMB)
    }
    
    /// Estimate memory requirement for a model
    private static func estimateMemoryRequirement(at url: URL, fileManager: FileManager) -> Int? {
        guard let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            return nil
        }
        
        var totalBytes: Int64 = 0
        for fileURL in contents where fileURL.pathExtension == "safetensors" {
            if let resources = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let fileSize = resources.fileSize {
                totalBytes += Int64(fileSize)
            }
        }
        
        // Rough estimate: file size + overhead for model loading (~1.5x)
        let estimatedBytes = Double(totalBytes) * 1.5
        return Int(estimatedBytes / 1_000_000) // Convert to MB
    }
    
    /// Validate MLX model
    private static func validateMLXModel(
        at url: URL,
        fileManager: FileManager,
        issues: inout [String],
        warnings: inout [String],
        estimatedMemoryMB: Int?
    ) -> ModelValidationResult {
        // Check for config.json
        let configURL = url.appendingPathComponent("config.json")
        if !fileManager.fileExists(atPath: configURL.path) {
            issues.append("Missing config.json")
        } else {
            // Validate config.json has model_type and sanity-check common fields
            if let data = try? Data(contentsOf: configURL),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if json["model_type"] == nil {
                    issues.append("config.json missing model_type")
                }
                if let textConfig = json["text_config"] as? [String: Any],
                   let intermediate = textConfig["intermediate_size"] {
                    if intermediate is [Any] {
                        issues.append("text_config.intermediate_size is an array; expected a single integer (use an MLX-converted checkpoint)")
                    }
                }
            } else {
                issues.append("config.json is invalid or unreadable")
            }
        }
        
        // Check for model weights
        let safetensorsFiles = (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]))
            .map { $0.filter { $0.pathExtension == "safetensors" } } ?? []
        
        let indexFile = url.appendingPathComponent("model.safetensors.index.json")
        
        if safetensorsFiles.isEmpty && !fileManager.fileExists(atPath: indexFile.path) {
            issues.append("No model weights found (expected .safetensors files or model.safetensors.index.json)")
        }
        
        // Check for tokenizer
        let tokenizerFiles = ["tokenizer.json", "tokenizer_config.json"]
        var hasTokenizer = false
        for fileName in tokenizerFiles {
            if fileManager.fileExists(atPath: url.appendingPathComponent(fileName).path) {
                hasTokenizer = true
                break
            }
        }
        
        if !hasTokenizer {
            warnings.append("Tokenizer files not found. Text generation may not work properly.")
        }
        
        // Memory warning
        if let memoryMB = estimatedMemoryMB, memoryMB > 4000 {
            warnings.append("Model requires approximately \(memoryMB)MB of memory, which may cause performance issues on some devices.")
        }
        
        return ModelValidationResult(
            isValid: issues.isEmpty,
            format: .mlx,
            issues: issues,
            warnings: warnings,
            estimatedMemoryMB: estimatedMemoryMB
        )
    }

    /// Get helpful error message from validation result
    public static func errorMessage(from result: ModelValidationResult) -> String {
        var message = "Model validation failed:\n\n"
        
        if !result.issues.isEmpty {
            message += "Issues:\n"
            for issue in result.issues {
                message += "• \(issue)\n"
            }
        }
        
        if !result.warnings.isEmpty {
            message += "\nWarnings:\n"
            for warning in result.warnings {
                message += "• \(warning)\n"
            }
        }
        
        if let memory = result.estimatedMemoryMB {
            message += "\nEstimated memory requirement: \(memory)MB\n"
        }
        
        return message
    }
    
    /// Get suggested actions from validation result
    public static func suggestedActions(from result: ModelValidationResult) -> [String] {
        var actions: [String] = []
        
        for issue in result.issues {
            if issue.contains("not found") || issue.contains("does not exist") {
                actions.append("Download the model using the model manager or check the model path")
            } else if issue.contains("config.json") {
                actions.append("Ensure the model was properly converted to MLX format")
            } else if issue.contains("weights") {
                actions.append("Re-download or re-convert the model weights")
            }
        }
        
        return actions
    }
}




