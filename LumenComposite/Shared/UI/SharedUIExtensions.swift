import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
public struct RenameConversationSheet: View {
    public let title: String
    @Binding public var newTitle: String
    public var onCancel: () -> Void
    public var onSave: (String) -> Void
    
    public init(title: String, newTitle: Binding<String>, onCancel: @escaping () -> Void, onSave: @escaping (String) -> Void) {
        self.title = title
        self._newTitle = newTitle
        self.onCancel = onCancel
        self.onSave = onSave
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Conversation title", text: $newTitle)
                        .textFieldStyle(.roundedBorder)
                }
                Section {
                    Text("Give your chat a memorable name so you can find it later. Names stay local to your device.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Rename Conversation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(newTitle.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// Legacy ThreadRow - kept for compatibility but not used in new design
public struct ThreadRow: View {
    public let thread: ChatThread
    @ObservedObject public var state: AppState
    
    public init(thread: ChatThread, state: AppState) {
        self.thread = thread
        self.state = state
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(thread.title)
                .lineLimit(1)
                .font(.body)
            if !thread.modelId.isEmpty {
                Text(thread.modelId)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

public extension View {
    @ViewBuilder
    func listSectionSpacingCompat(_ value: CGFloat) -> some View {
        if #available(iOS 17.0, *) {
            self.listSectionSpacing(value)
        } else {
            self
        }
    }
}

public struct IOSTopBarPillView: View {
    public let modelName: String
    public let statusText: String
    public let statusColor: Color
    public let onTapSettings: () -> Void
    
    public init(modelName: String, statusText: String, statusColor: Color, onTapSettings: @escaping () -> Void) {
        self.modelName = modelName
        self.statusText = statusText
        self.statusColor = statusColor
        self.onTapSettings = onTapSettings
    }
    
    public var body: some View {
        HStack {
            // Model Name
            Text(modelName.isEmpty ? "Lumen" : modelName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
            
            Spacer()
            
            // Status Indicator
            if !statusText.isEmpty {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text(statusText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
            }
            
            // Settings Button
            Button(action: onTapSettings) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
        .overlay(
            Capsule()
                .stroke(.white.opacity(0.2), lineWidth: 0.5)
        )
    }
}

public struct ShareSheet: UIViewControllerRepresentable {
    public let activityItems: [Any]
    
    public init(activityItems: [Any]) {
        self.activityItems = activityItems
    }
    
    public func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

#if os(macOS)
// Editable thread row for macOS sidebar
public struct EditableThreadRow: View {
    public let thread: ChatThread
    @ObservedObject public var state: AppState
    @State private var isEditing = false
    @State private var editedTitle: String = ""
    
    public init(thread: ChatThread, state: AppState) {
        self.thread = thread
        self.state = state
    }
    
    public var body: some View {
        HStack {
            if isEditing {
                TextField("Thread name", text: $editedTitle)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        commitEdit()
                    }
                    .onExitCommand {
                        cancelEdit()
                    }
            } else {
                Text(thread.title)
                    .lineLimit(1)
                Spacer()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            startEditing()
        }
        .onChange(of: thread.id) { _ in
            if thread.id == state.selectedThreadID {
                editedTitle = thread.title
            }
        }
    }
    
    private func startEditing() {
        editedTitle = thread.title
        isEditing = true
    }
    
    private func commitEdit() {
        if !editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            state.updateThreadTitle(thread.id, to: editedTitle.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        isEditing = false
    }
    
    private func cancelEdit() {
        isEditing = false
        editedTitle = thread.title
    }
}
#endif

public func knowledgeBaseDocumentTypes() -> [UTType] {
    var types: [UTType] = [
        .plainText,
        .utf8PlainText,
        .utf16PlainText,
        .text,
        .content,
        .rtf,
        .rtfd,
        .pdf
    ]
    
    if let markdownType = UTType(filenameExtension: "md") {
        types.append(markdownType)
    }
    
    if let doc = UTType(filenameExtension: "doc") {
        types.append(doc)
    }
    if let docx = UTType(filenameExtension: "docx") {
        types.append(docx)
    }
    if let html = UTType(filenameExtension: "html") {
        types.append(html)
    }
    return types
}
