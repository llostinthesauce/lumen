import SwiftUI

public struct MessageBubble: View {
    let message: Message
    var isStreaming: Bool = false
    var showGenerating: Bool = false
    var onCopy: ((Message) -> Void)? = nil
    var onEdit: ((Message) -> Void)? = nil
    var onDelete: ((Message) -> Void)? = nil
    var onRegenerate: (() -> Void)? = nil
    
    @State private var showActions = false
    #if os(macOS)
    @State private var isHovered = false
    #endif
    #if os(iOS)
    @Environment(\.colorScheme) private var colorScheme
    #endif
    
    private var actionButtonBackgroundColor: Color {
        #if os(macOS)
        return Color(NSColor.controlBackgroundColor).opacity(0.8)
        #else
        return Color(.systemBackground).opacity(0.8)
        #endif
    }
    
    public init(message: Message, isStreaming: Bool = false, showGenerating: Bool = false, onCopy: ((Message) -> Void)? = nil, onEdit: ((Message) -> Void)? = nil, onDelete: ((Message) -> Void)? = nil, onRegenerate: (() -> Void)? = nil) {
        self.message = message
        self.isStreaming = isStreaming
        self.showGenerating = showGenerating
        self.onCopy = onCopy
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.onRegenerate = onRegenerate
    }
    
    public var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user {
                Spacer(minLength: 50)
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 8) {
                    #if os(macOS)
                    if message.role == .assistant {
                        actionButtons
                    }
                    #endif
                    
                    VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                        if showGenerating {
                            HStack(spacing: 8) {
                                GeneratingIndicator()
                                Text("Generating...")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                        } else if !message.text.isEmpty {
                            Text(message.text)
                                .textSelection(.enabled)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
#if os(iOS)
                                .background(message.role == .user ? userBubbleColor : assistantBubbleColor)
#else
                                .background(
                                    message.role == .user 
                                        ? Color(red: 0.0, green: 0.5, blue: 0.9)
                                        : Color.white.opacity(0.85)
                                )
#endif
                                .foregroundStyle(
                                    message.role == .user 
                                        ? .white 
                                        : .primary
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                        }
                    }
                    #if os(macOS)
                    if message.role == .user {
                        actionButtons
                    }
                    #endif
                }
                if message.role == .assistant,
                   let sources = message.referencedDocuments,
                   !sources.isEmpty {
                    DocumentSourcesView(sources: sources)
                        .frame(maxWidth: 420, alignment: .leading)
                }
                if isStreaming && !showGenerating && !message.text.isEmpty {
                    HStack(spacing: 4) {
                        TypingDot(delay: 0)
                        TypingDot(delay: 0.2)
                        TypingDot(delay: 0.4)
                    }
                    .padding(.leading, 12)
                    .padding(.top, 4)
                }
            }
            if message.role == .assistant {
                Spacer(minLength: 50)
            }
        }
        #if os(macOS)
        .onHover { hovering in
            isHovered = hovering
        }
        #endif
    }
    
    #if os(macOS)
    @ViewBuilder
    private var actionButtons: some View {
        if isHovered || showActions {
            HStack(spacing: 4) {
                if let onCopy = onCopy {
                    Button(action: { onCopy(message) }) {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                if message.role == .user, let onEdit = onEdit {
                    Button(action: { onEdit(message) }) {
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                if message.role == .assistant, let onRegenerate = onRegenerate, !isStreaming {
                    Button(action: { onRegenerate() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                if let onDelete = onDelete {
                    Button(action: { onDelete(message) }) {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(actionButtonBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
    #endif
    
    #if os(iOS)
    private var userBubbleColor: Color {
        if colorScheme == .dark {
            return Color.accentColor.opacity(0.6)
        } else {
            return Color.accentColor.opacity(0.85)
        }
    }
    
    private var assistantBubbleColor: Color {
        if colorScheme == .dark {
            return Color(UIColor.secondarySystemBackground).opacity(0.95)
        } else {
            return Color(UIColor.systemBackground).opacity(0.95)
        }
    }
    #endif
}

public struct DocumentSourcesView: View {
    let sources: [String]
    
    private var formattedSources: String {
        sources.joined(separator: ", ")
    }
    
    public var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 1)
            Text(formattedSources)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.12))
        )
    }
}

public struct GeneratingIndicator: View {
    @State private var rotation: Double = 0
    
    public var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: 16, height: 16)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

public struct TypingDot: View {
    let delay: Double
    @State private var opacity: Double = 0.3
    
    public var body: some View {
        Circle()
            .fill(Color.secondary)
            .frame(width: 6, height: 6)
            .opacity(opacity)
            .onAppear {
                withAnimation(
                    Animation.easeInOut(duration: 0.6)
                        .repeatForever()
                        .delay(delay)
                ) {
                    opacity = opacity == 0.3 ? 0.8 : 0.3
                }
            }
    }
}
