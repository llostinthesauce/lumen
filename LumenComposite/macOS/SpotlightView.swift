#if os(macOS)
import SwiftUI

struct SpotlightView: View {
    @ObservedObject var state: AppState
    @ObservedObject var sessionController: ChatSessionController
    var onClose: () -> Void
    
    @State private var input: String = ""
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            inputSection
            responseSection
        }
        .frame(width: 700)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .onAppear { isInputFocused = true }
    }
    
    private func submit() {
        guard !input.isEmpty else { return }
        let text = input
        input = ""
        
        Task {
            await sessionController.send(text: text, selectedModel: state.selectedThread?.modelId ?? "")
        }
    }
    
    @ViewBuilder
    private var inputSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary)
            
            TextField("Ask Lumen...", text: $input)
                .font(.system(size: 24, weight: .light))
                .textFieldStyle(.plain)
                .focused($isInputFocused)
                .onSubmit { submit() }
            
            if !input.isEmpty {
                Button(action: { input = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: { onClose() }) {
                    Image(systemName: "escape")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .background(.ultraThinMaterial)
    }
    
    @ViewBuilder
    private var responseSection: some View {
        if let thread = state.selectedThread, !thread.messages.isEmpty {
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(thread.messages.suffix(1)) { message in
                        if message.role == .assistant {
                            Text(message.text)
                                .font(.system(size: 16))
                                .textSelection(.enabled)
                        }
                    }
                    
                    if sessionController.isStreaming {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("Thinking...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(20)
            }
            .frame(maxHeight: 400)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
}
#else
import SwiftUI

struct SpotlightView: View {
    var body: some View { EmptyView() }
}
#endif
