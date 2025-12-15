import Foundation
import os

public struct ModelDefaultsEntry: Codable, Hashable {
    public enum ModelType: String, Codable {
        case text
        case visionText = "vision_text"
        case image
    }
    
    public let type: ModelType
    public var temperature: Double?
    public var topP: Double?
    public var topK: Int?
    public var maxNewTokens: Int?
    public var maxContextTokens: Int?
    public var numInferenceSteps: Int?
    public var guidanceScale: Double?
    public var width: Int?
    public var height: Int?
    public var tags: [String]?
    
    enum CodingKeys: String, CodingKey {
        case type
        case temperature
        case topP = "top_p"
        case topK = "top_k"
        case maxNewTokens = "max_new_tokens"
        case maxContextTokens = "max_context_tokens"
        case numInferenceSteps = "num_inference_steps"
        case guidanceScale = "guidance_scale"
        case width
        case height
        case tags
    }
}

public final class ModelDefaultsRegistry {
    public static let shared = ModelDefaultsRegistry()
    
    private let logger = Logger(subsystem: "com.lumen.app", category: "ModelDefaults")
    private let fileURL: URL
    private(set) var entries: [String: ModelDefaultsEntry] = [:]
    
    init(fileURL: URL = ModelDefaultsRegistry.resolveDefaultsFileURL()) {
        self.fileURL = fileURL
        // Always replace the on-disk defaults with the bundled copy on launch to avoid stale limits.
        Self.ensureSeedFile(at: fileURL, forceReplaceFromBundle: true)
        enforceLegacyResetIfNeeded()
        refreshFromBundledIfStale()
        reload()
    }
    
    public func reload() {
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            entries = try decoder.decode([String: ModelDefaultsEntry].self, from: data)
        } catch {
            logger.error("Failed to load model defaults: \(error.localizedDescription, privacy: .public)")
            entries = [:]
        }
    }
    
    public func config(for modelId: String) -> InferenceConfig? {
        guard let entry = entry(for: modelId) else { return nil }
        var config = InferenceConfig()
        if let maxKV = entry.maxContextTokens {
            config.maxKV = maxKV
        }
        if let maxTokens = entry.maxNewTokens {
            config.maxTokens = maxTokens
        }
        if let temperature = entry.temperature {
            config.temperature = temperature
        }
        if let topP = entry.topP {
            config.topP = topP
        }
        config.systemPrompt = "You are a helpful, concise assistant."
        config.profile = nil
        return config
    }
    
    public func entry(for modelId: String) -> ModelDefaultsEntry? {
        if let entry = entries[modelId] {
            return entry
        }
        return entries["default-config"]
    }

    /// Remove local defaults and reseed from the bundled copy.
    public func reseedFromBundle() {
        let fm = FileManager.default
        try? fm.removeItem(at: fileURL)
        Self.ensureSeedFile(at: fileURL, forceReplaceFromBundle: true)
        refreshFromBundledIfStale()
        reload()
    }

    /// Detect old/stale defaults (e.g., legacy 16k contexts) and reseed automatically.
    private func enforceLegacyResetIfNeeded() {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else { return }
        // Legacy signatures we want to purge (oversized 16k contexts).
        if text.contains("\"max_context_tokens\": 16384") {
            reseedFromBundle()
        }
    }
    
    private static func ensureSeedFile(at url: URL, forceReplaceFromBundle: Bool = false) {
        let fm = FileManager.default
        let directory = url.deletingLastPathComponent()
        if !fm.fileExists(atPath: directory.path) {
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        if fm.fileExists(atPath: url.path) {
            if !forceReplaceFromBundle { return }
            // Remove stale copy so the bundled defaults can be copied without error.
            try? fm.removeItem(at: url)
        }
        if let bundled = bundleDefaultsURL() {
            do {
                try fm.copyItem(at: bundled, to: url)
                return
            } catch {
                Logger(subsystem: "com.lumen.app", category: "ModelDefaults")
                    .error("Failed to copy bundled defaults: \(error.localizedDescription, privacy: .public)")
            }
        }
        do {
            try seedJSON.data(using: .utf8)?.write(to: url)
        } catch {
            Logger(subsystem: "com.lumen.app", category: "ModelDefaults")
                .error("Failed to seed model defaults file: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    private static func bundleDefaultsURL() -> URL? {
        #if SWIFT_PACKAGE
        #if os(iOS)
        return Bundle.module.url(forResource: "model-defaults-ios", withExtension: "json")
        #else
        return Bundle.module.url(forResource: "model-defaults-macos", withExtension: "json")
        #endif
        #else
        #if os(iOS)
        return Bundle.main.url(forResource: "model-defaults-ios", withExtension: "json")
        #else
        return Bundle.main.url(forResource: "model-defaults-macos", withExtension: "json")
        #endif
        #endif
    }
    
    private static func resolveDefaultsFileURL() -> URL {
        if let override = externalDefaultsURL() {
            return override
        }
        return AppDirs.modelDefaults
    }
    
    private static func externalDefaultsURL() -> URL? {
        #if os(iOS)
        #if targetEnvironment(simulator)
        if let hostHome = ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"] {
            let candidate = URL(fileURLWithPath: hostHome)
                .appendingPathComponent("Documents/KnowledgeBase/model-defaults.json", isDirectory: false)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        #endif
        #endif
        return nil
    }
    
    private static var seedJSON: String {
        #if os(macOS)
        return """
{
  "platform": "macOS-m1pro-16gb",

  "default-config": {
    "type": "text",
    "temperature": 0.6,
    "top_p": 0.9,
    "top_k": 40,
    "max_new_tokens": 1024,
    "max_context_tokens": 8192,
    "tags": ["fallback", "average"]
  },

  "Llama-3.2-3B-Instruct-mlx-4Bit": {
    "type": "text",
    "temperature": 0.6,
    "top_p": 0.9,
    "top_k": 40,
    "max_new_tokens": 1024,
    "max_context_tokens": 8192,
    "tags": ["llama3.2", "3b", "instruct", "bundled", "long-context-native-128k"]
  },

  "SmolLM3-3B-4bit": {
    "type": "text",
    "temperature": 0.65,
    "top_p": 0.9,
    "top_k": 40,
    "max_new_tokens": 1024,
    "max_context_tokens": 8192,
    "tags": ["smollm3", "3b", "bundled", "long-context-native-128k"]
  },

  "granite-4.0-h-micro-4bit": {
    "type": "text",
    "temperature": 0.55,
    "top_p": 0.9,
    "top_k": 40,
    "max_new_tokens": 1024,
    "max_context_tokens": 8192,
    "tags": ["granite", "3b", "micro", "bundled", "long-context-native-128k"]
  },

  "VibeThinker-1.5B-mlx-4bit": {
    "type": "text",
    "temperature": 0.7,
    "top_p": 0.95,
    "top_k": 40,
    "max_new_tokens": 1024,
    "max_context_tokens": 12288,
    "tags": ["vibethinker", "1.5b", "reasoning", "bundled-or-user"]
  },

  "OpenELM-1_1B-Instruct-8bit": {
    "type": "text",
    "temperature": 0.7,
    "top_p": 0.95,
    "top_k": 40,
    "max_new_tokens": 512,
    "max_context_tokens": 2048,
    "tags": ["openelm", "1.1b", "fast", "bundled"]
  },

  "Mistral-7B-Instruct-v0.3-mlx-4bit": {
    "type": "text",
    "temperature": 0.6,
    "top_p": 0.9,
    "top_k": 40,
    "max_new_tokens": 768,
    "max_context_tokens": 4096,
    "tags": ["mistral", "7b", "instruct", "user", "heavier"]
  },
  "gemma-3-4b-it-qat-4bit": {
    "type": "vision_text",
    "temperature": 0.6,
    "top_p": 0.9,
    "top_k": 40,
    "max_new_tokens": 1024,
    "max_context_tokens": 8192,
    "tags": [
      "gemma-3",
      "4b",
      "it",
      "qat",
      "vision",
      "multimodal",
      "long-context-128k",
      "macos-ok"
    ]
  },


  "gemma-3n-E4B-it-MLX-4bit": {
    "type": "vision_text",
    "temperature": 0.6,
    "top_p": 0.9,
    "top_k": 40,
    "max_new_tokens": 768,
    "max_context_tokens": 4096,
    "tags": ["gemma-3n", "e4b", "it", "multimodal", "edge-optimized"]
  },

  "Qwen3-VL-4B-Instruct-MLX-4bit": {
    "type": "vision_text",
    "temperature": 0.7,
    "top_p": 0.8,
    "top_k": 20,
    "max_new_tokens": 1024,
    "max_context_tokens": 8192,
    "tags": ["qwen3", "vl", "4b", "vision", "bundled", "long-context-native-256k"]
  },

  "Qwen3-VL-4B-Instruct-MLX-8bit": {
    "type": "vision_text",
    "temperature": 0.7,
    "top_p": 0.8,
    "top_k": 20,
    "max_new_tokens": 768,
    "max_context_tokens": 3072,
    "tags": ["qwen3", "vl", "4b", "vision", "8bit", "user", "heavy"]
  },

  "bge-small-en-v1.5-bf16": {
    "type": "text",
    "temperature": 0.1,
    "top_p": 0.9,
    "top_k": 40,
    "max_new_tokens": 0,
    "max_context_tokens": 512,
    "tags": ["embedding", "bge-small", "mlx"]
  },

  "bge-m3": {
    "type": "text",
    "temperature": 0.1,
    "top_p": 0.9,
    "top_k": 40,
    "max_new_tokens": 64,
    "max_context_tokens": 8192,
    "tags": ["embedding", "bge-m3", "dense+lexical", "user", "heavy-embedding"]
  },

  "all-MiniLM-L6-v2-8bit": {
    "type": "text",
    "temperature": 0.1,
    "top_p": 0.9,
    "top_k": 40,
    "max_new_tokens": 64,
    "max_context_tokens": 2048,
    "tags": ["embedding", "miniLM", "bundled", "light-embedding"]
  },

  "mlx-stable-diffusion-3.5-large-4bit-quantized": {
    "type": "image",
    "num_inference_steps": 30,
    "guidance_scale": 5.5,
    "width": 768,
    "height": 768,
    "tags": ["sd3.5", "mlx", "user", "heavy-image-model"]
  }
}
"""
        #else
        return """
{
  "platform": "iOS-iphone15pro-8gb",

  "default-config": {
    "type": "text",
    "temperature": 0.6,
    "top_p": 0.9,
    "top_k": 40,
    "max_new_tokens": 512,
    "max_context_tokens": 4096,
    "tags": ["fallback", "mobile-default", "iphone15pro"]
  },

  "Llama-3.2-3B-Instruct-mlx-4Bit": {
    "type": "text",
    "temperature": 0.55,
    "top_p": 0.9,
    "top_k": 40,
    "max_new_tokens": 512,
    "max_context_tokens": 4096,
    "tags": ["llama3.2", "3b", "instruct", "bundled", "ios-ok", "iphone15pro-default"]
  },

  "SmolLM3-3B-4bit": {
    "type": "text",
    "temperature": 0.65,
    "top_p": 0.9,
    "top_k": 40,
    "max_new_tokens": 512,
    "max_context_tokens": 4096,
    "tags": ["smollm3", "3b", "bundled", "ios-ok", "iphone15pro-default"]
  },

  "granite-4.0-h-micro-4bit": {
    "type": "text",
    "temperature": 0.55,
    "top_p": 0.9,
    "top_k": 40,
    "max_new_tokens": 448,
    "max_context_tokens": 3584,
    "tags": ["granite", "3b", "micro", "bundled", "ios-ok", "iphone15pro-default"]
  },

  "VibeThinker-1.5B-mlx-4bit": {
    "type": "text",
    "temperature": 0.7,
    "top_p": 0.95,
    "top_k": 40,
    "max_new_tokens": 512,
    "max_context_tokens": 6144,
    "tags": ["vibethinker", "1.5b", "reasoning", "ios-ok"]
  },

  "OpenELM-1_1B-Instruct-8bit": {
    "type": "text",
    "temperature": 0.65,
    "top_p": 0.9,
    "top_k": 40,
    "max_new_tokens": 320,
    "max_context_tokens": 2048,
    "tags": ["openelm", "1.1b", "fast", "bundled", "ios-ok", "iphone15pro-default"]
  },

  "gemma-3n-E4B-it-MLX-4bit": {
    "type": "vision_text",
    "temperature": 0.6,
    "top_p": 0.9,
    "top_k": 40,
    "max_new_tokens": 384,
    "max_context_tokens": 3072,
    "tags": ["gemma-3n", "e4b", "it", "multimodal", "edge-optimized", "ios-ok"]
  },
  
  "gemma-3n-E2B-it-lm-4bit": {
    "type": "vision_text",
    "temperature": 0.6,
    "top_p": 0.9,
    "top_k": 32,
    "max_new_tokens": 352,
    "max_context_tokens": 3072,
    "tags": ["gemma-3n", "e2b", "it", "multimodal", "iphone15pro-default"]
  },
  "gemma-3-4b-it-qat-4bit": {
    "type": "vision_text",
    "temperature": 0.6,
    "top_p": 0.9,
    "top_k": 40,
    "max_new_tokens": 512,
    "max_context_tokens": 4096,
    "tags": [
      "gemma-3",
      "4b",
      "it",
      "qat",
      "vision",
      "multimodal",
      "ios-heavy-optional"
    ]
  },


  "Qwen3-VL-4B-Instruct-MLX-4bit": {
    "type": "vision_text",
    "temperature": 0.7,
    "top_p": 0.8,
    "top_k": 20,
    "max_new_tokens": 512,
    "max_context_tokens": 4096,
    "tags": ["qwen3", "vl", "4b", "vision", "bundled", "long-context-native-256k", "ios-ok"]
  },

  "Qwen3-VL-4B-Instruct-MLX-8bit": {
    "type": "vision_text",
    "temperature": 0.7,
    "top_p": 0.8,
    "top_k": 20,
    "max_new_tokens": 256,
    "max_context_tokens": 2048,
    "tags": ["qwen3", "vl", "4b", "vision", "8bit", "user", "heavy", "ios-very-heavy"]
  },
  
  "Qwen3-VL-2B-Instruct-MLX-8bit": {
    "type": "vision_text",
    "temperature": 0.6,
    "top_p": 0.85,
    "top_k": 20,
    "max_new_tokens": 320,
    "max_context_tokens": 2048,
    "tags": ["qwen3", "vl", "2b", "vision", "iphone15pro-default"]
  },

  "all-MiniLM-L6-v2-8bit": {
    "type": "text",
    "temperature": 0.1,
    "top_p": 0.9,
    "top_k": 40,
    "max_new_tokens": 0,
    "max_context_tokens": 1024,
    "tags": ["embedding", "miniLM", "bundled", "light-embedding", "ios-fast"]
  },

  "bge-small-en-v1.5-bf16": {
    "type": "text",
    "temperature": 0.1,
    "top_p": 0.9,
    "top_k": 40,
    "max_new_tokens": 0,
    "max_context_tokens": 512,
    "tags": ["embedding", "bge-small", "mlx", "ios-ok"]
  },

  "bge-m3": {
    "type": "text",
    "temperature": 0.1,
    "top_p": 0.9,
    "top_k": 40,
    "max_new_tokens": 0,
    "max_context_tokens": 4096,
    "tags": ["embedding", "bge-m3", "dense+lexical", "user", "heavy-embedding", "ios-heavy"]
  }
}
"""
        #endif
    }

    /// If the on-disk defaults differ from the bundled copy, refresh them (with a simple backup).
    private func refreshFromBundledIfStale() {
        guard let bundled = Self.bundleDefaultsURL(),
              let bundledData = try? Data(contentsOf: bundled),
              let existingData = try? Data(contentsOf: fileURL),
              existingData != bundledData else {
            return
        }
        
        let fm = FileManager.default
        // Keep a single backup of the old file before replacing.
        let backupURL = fileURL.appendingPathExtension("bak")
        if fm.fileExists(atPath: backupURL.path) {
            try? fm.removeItem(at: backupURL)
        }
        try? fm.copyItem(at: fileURL, to: backupURL)
        do {
            try fm.removeItem(at: fileURL)
            try fm.copyItem(at: bundled, to: fileURL)
            logger.log("Refreshed model-defaults from bundled copy (stale on-disk file replaced)")
        } catch {
            logger.error("Failed to refresh model-defaults from bundle: \(error.localizedDescription, privacy: .public)")
        }
    }
}
