import Foundation

public enum PromptBuilder {
    public static func build(messages: [Message], system: String) -> String {
        var parts: [String] = ["System: \(system)"]
        for m in messages {
            switch m.role {
            case .user: parts.append("User: \(m.text)")
            case .assistant: parts.append("Assistant: \(m.text)")
            case .system: parts.append("System: \(m.text)")
            }
        }
        parts.append("Assistant:")
        return parts.joined(separator: "\n")
    }
}
