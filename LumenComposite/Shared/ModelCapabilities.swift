import Foundation

public struct ModelCapabilities: OptionSet {
    public let rawValue: Int
    
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    public static let visionInput = ModelCapabilities(rawValue: 1 << 0)
}

struct ModelCapabilityDetector {
    static func capabilities(for modelId: String, modelURL: URL?) -> ModelCapabilities {
        var capabilities: ModelCapabilities = []
        let lowercased = modelId.lowercased()
        
        if lowercased.contains("vl") ||
            lowercased.contains("vision") ||
            lowercased.contains("multimodal") ||
            lowercased.contains("llava") {
            capabilities.insert(.visionInput)
        }
        
        return capabilities
    }
}
