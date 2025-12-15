import Foundation

public enum InferenceProfile: String, Codable, CaseIterable {
    case low = "Low"
    case balanced = "Balanced"
    case max = "Max"
    
    private static func maxTokensKey(for profile: InferenceProfile) -> String {
        "inference.profile.maxTokens.\(profile.rawValue)"
    }
    
    /// Context size (in tokens) for this profile
    public var contextSize: Int {
        switch self {
        case .low: return 2048
        case .balanced: return 4096
        case .max: return 8192
        }
    }
    
    /// Default temperature for this profile
    public var temperature: Double {
        switch self {
        case .low: return 0.5
        case .balanced: return 0.7
        case .max: return 0.9
        }
    }
    
    /// Default max tokens for this profile
    public var maxTokens: Int {
        let stored = UserDefaults.standard.integer(forKey: Self.maxTokensKey(for: self))
        if stored > 0 { return stored }
        return defaultMaxTokens
    }
    
    private var defaultMaxTokens: Int {
        #if os(iOS)
        switch self {
        case .low: return 160
        case .balanced: return 320
        case .max: return 640
        }
        #else
        switch self {
        case .low: return 256
        case .balanced: return 512
        case .max: return 1024
        }
        #endif
    }
    
    public static func setMaxTokens(_ value: Int, for profile: InferenceProfile) {
        let clamped = Swift.max(32, Swift.min(value, 4096))
        UserDefaults.standard.set(clamped, forKey: maxTokensKey(for: profile))
    }
    
    /// Default max KV cache size
    public var maxKV: Int {
        #if os(iOS)
        switch self {
        case .low: return 64
        case .balanced: return 160
        case .max: return 256
        }
        #else
        switch self {
        case .low: return 128
        case .balanced: return 256
        case .max: return 512
        }
        #endif
    }
    
    /// Default topP value
    public var topP: Double {
        switch self {
        case .low: return 0.9
        case .balanced: return 0.95
        case .max: return 0.98
        }
    }
    
    /// Create an InferenceConfig from this profile
    public func toConfig() -> InferenceConfig {
        InferenceConfig(
            maxKV: maxKV,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            systemPrompt: "You are a helpful, concise assistant.",
            trustRemoteCode: false,
            profile: self
        )
    }
    
    /// Create an InferenceConfig from this profile, adjusted for model size
    public func toConfig(forModelSize modelSize: ModelSize) -> InferenceConfig {
        var config = toConfig()
        
        // Adjust context size based on model size
        // Smaller models may not support large contexts
        switch modelSize {
        case .small: // < 1B parameters
            config.maxKV = min(maxKV, 128)
            config.maxTokens = min(maxTokens, 256)
        case .medium: // 1-7B parameters
            config.maxKV = min(maxKV, 256)
            config.maxTokens = min(maxTokens, 512)
        case .large: // > 7B parameters
            // Use full profile settings
            break
        }
        
        return config
    }
}

public enum ModelSize {
    case small    // < 1B parameters
    case medium   // 1-7B parameters
    case large    // > 7B parameters
    
    /// Estimate model size from model name/ID
    public static func estimate(from modelId: String) -> ModelSize {
        let lowercased = modelId.lowercased()
        
        // Check for explicit size indicators
        if lowercased.contains("135m") || lowercased.contains("270m") || lowercased.contains("0.5b") {
            return .small
        }
        if lowercased.contains("1b") || lowercased.contains("3b") || lowercased.contains("7b") {
            return .medium
        }
        if lowercased.contains("8b") || lowercased.contains("13b") || lowercased.contains("70b") {
            return .large
        }
        
        // Default to medium if unclear
        return .medium
    }
}

public struct InferenceConfig: Codable, Hashable {
    public var maxKV: Int = 256
    public var maxTokens: Int = 256
    public var temperature: Double = 0.7
    public var topP: Double = 0.95
    public var systemPrompt: String = "You are a helpful, concise assistant."
    public var trustRemoteCode: Bool = false
    public var profile: InferenceProfile? = .balanced // 2.1: Optional profile field
    
    public init(maxKV: Int = 256, maxTokens: Int = 256, temperature: Double = 0.7, topP: Double = 0.95, systemPrompt: String = "You are a helpful, concise assistant.", trustRemoteCode: Bool = false, profile: InferenceProfile? = .balanced) {
        self.maxKV = maxKV
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.systemPrompt = systemPrompt
        self.trustRemoteCode = trustRemoteCode
        self.profile = profile
    }
    
    /// Create config from a profile (2.2: Preset factory)
    public static func preset(for profile: InferenceProfile, modelSize: ModelSize = .medium) -> InferenceConfig {
        var config = profile.toConfig(forModelSize: modelSize)
        config.profile = profile
        return config
    }
    
    /// Create config from a profile (backward compatibility)
    public static func from(_ profile: InferenceProfile, modelSize: ModelSize = .medium) -> InferenceConfig {
        preset(for: profile, modelSize: modelSize)
    }
}
