import Foundation

/// Model formats supported by the app (MLX-only).
public enum ModelFormat {
    case mlx              // MLX format (safetensors + config.json)
    case unknown          // Unknown or unsupported format
}

/// Detects the format of a model directory.
public struct ModelFormatDetector {
    /// Detect the model format from a directory URL.
    public static func detectFormat(at url: URL) -> ModelFormat {
        let fm = FileManager.default
        return hasMLXModel(at: url, fileManager: fm) ? .mlx : .unknown
    }

    private static let mlxSupportedTypes = [
        "mistral", "llama", "phi", "phi3", "phimoe", "gemma", "gemma2", "gemma3",
        "gemma3_text", "gemma3n", "qwen2", "qwen3", "qwen3_moe", "starcoder2",
        "cohere", "openelm", "internlm2", "deepseek_v3", "granite", "granitemoehybrid",
        "mimo", "glm4", "acereason", "falcon_h1", "bitnet", "smollm3", "ernie4_5",
        "lfm2", "baichuan_m1", "exaone4", "gpt_oss", "lille-130m", "olmoe", "olmo2",
        "bailing_moe", "lfm2_moe", "nanochat"
    ]

    private static let transformersOnlyTypes = [
        "gpt2", "bert", "roberta", "xlm-roberta", "electra", "distilbert", "albert",
        "bart", "marian", "mbart", "bloom", "opt", "falcon", "mpt", "starcoder",
        "codegen", "t5", "gpt-j", "gpt-neo", "gpt-neox"
    ]

    /// Check if directory contains an MLX model.
    private static func hasMLXModel(at url: URL, fileManager: FileManager) -> Bool {
        if let configURL = findConfigJSON(in: url, fileManager: fileManager) ??
            (fileManager.fileExists(atPath: url.appendingPathComponent("config.json").path) ? url.appendingPathComponent("config.json") : nil) {
            if let data = try? Data(contentsOf: configURL),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let modelType = json["model_type"] as? String {
                let lowercased = modelType.lowercased()
                if transformersOnlyTypes.contains(where: { lowercased.contains($0) }) {
                    return false
                }
                return mlxSupportedTypes.contains(where: { lowercased.contains($0) }) ||
                       hasMLXFiles(at: url, fileManager: fileManager)
            }
        }
        return hasMLXFiles(at: url, fileManager: fileManager)
    }

    private static func hasMLXFiles(at url: URL, fileManager: FileManager) -> Bool {
        let safetensorsFiles = (try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ))?.filter { $0.pathExtension == "safetensors" } ?? []
        return !safetensorsFiles.isEmpty || fileManager.fileExists(atPath: url.appendingPathComponent("model.safetensors.index.json").path)
    }

    /// Recursively find config.json with model_type.
    private static func findConfigJSON(in directory: URL, fileManager: FileManager) -> URL? {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for item in contents {
            let resourceValues = try? item.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
            let isDir = resourceValues?.isDirectory ?? false
            let isFile = resourceValues?.isRegularFile ?? false

            if isFile && item.lastPathComponent.lowercased() == "config.json" {
                return item
            } else if isDir && !item.lastPathComponent.hasPrefix(".") {
                if let found = findConfigJSON(in: item, fileManager: fileManager) {
                    return found
                }
            }
        }

        return nil
    }

    /// Get the display name for a model format.
    public static func formatName(_ format: ModelFormat) -> String {
        switch format {
        case .mlx:
            return "MLX"
        case .unknown:
            return "Unknown"
        }
    }
}
