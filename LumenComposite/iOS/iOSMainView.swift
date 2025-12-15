import SwiftUI

#if os(iOS)
struct iOSMainView: View {
    @ObservedObject var state: AppState
    @ObservedObject var sessionController: ChatSessionController
    @Binding var modelFolders: [String]
    @Binding var selectedModel: String
    
    @State private var showSettings = false
    @State private var showHistory = false // For iPhone slide-over menu if needed
    @State private var input: String = ""
    
    // Environment
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    var body: some View {
        // Use NavigationSplitView for iPad/Large iPhones, but ensure it behaves well
        NavigationSplitView {
            iOSSidebarView(state: state, showSettings: $showSettings)
        } detail: {
            if let thread = state.selectedThread {
                iOSChatView(
                    state: state,
                    sessionController: sessionController,
                    thread: thread,
                    input: $input,
                    selectedModel: $selectedModel
                )
            } else {
                iOSWelcomeView(showSettings: $showSettings)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(state: state, onRefresh: {
                // Refresh logic
            }, selectedModel: $selectedModel)
        }
    }
}

struct iOSSidebarView: View {
    @ObservedObject var state: AppState
    @Binding var showSettings: Bool
    
    var body: some View {
        List(selection: $state.selectedThreadID) {
            Section {
                Button(action: {
                    state.addThread(title: "New Chat", modelId: state.selectedThread?.modelId ?? "")
                }) {
                    Label("New Chat", systemImage: "square.and.pencil")
                        .foregroundStyle(.blue)
                }
            }
            
            Section("History") {
                ForEach(state.threads.sorted(by: { $0.statistics.lastActivity > $1.statistics.lastActivity })) { thread in
                    NavigationLink(value: thread.id) {
                        VStack(alignment: .leading) {
                            Text(thread.title.isEmpty ? "New Chat" : thread.title)
                                .font(.headline)
                                .lineLimit(1)
                            if let lastMsg = thread.messages.last {
                                Text(lastMsg.text)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            state.deleteThread(thread.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Lumen")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { showSettings = true }) {
                    Image(systemName: "gear")
                }
            }
        }
    }
}

struct iOSChatView: View {
    @ObservedObject var state: AppState
    @ObservedObject var sessionController: ChatSessionController
    let thread: ChatThread
    @Binding var input: String
    @Binding var selectedModel: String
    
    var body: some View {
        VStack(spacing: 0) {
            // Chat History
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(thread.messages) { message in
                            iOSMessageBubble(message: message)
                                .id(message.id)
                        }
                        
                        if sessionController.isStreaming && sessionController.activeStreamingThreadID == thread.id {
                            HStack {
                                ProgressView()
                                    .padding(8)
                                Spacer()
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: thread.messages.count) { _ in
                    if let last = thread.messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            // Input Area
            VStack(spacing: 0) {
                Divider()
                HStack(alignment: .bottom) {
                    TextField("Message...", text: $input, axis: .vertical)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(20)
                        .lineLimit(1...5)
                    
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(input.isEmpty ? .gray : .blue)
                    }
                    .disabled(input.isEmpty || sessionController.isStreaming)
                }
                .padding()
                .background(Color(.systemBackground))
            }
        }
        .navigationTitle(thread.title.isEmpty ? "Chat" : thread.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Model", selection: $selectedModel) {
                        ForEach(state.listModelFolders(), id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                } label: {
                    Text(selectedModel.isEmpty ? "Select Model" : selectedModel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    private func sendMessage() {
        guard !input.isEmpty else { return }
        let text = input
        input = ""
        
        Task {
            await sessionController.send(text: text, selectedModel: selectedModel)
        }
    }
}

struct iOSMessageBubble: View {
    let message: Message
    
    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
                Text(message.text)
                    .padding(12)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(16, corners: [.topLeft, .topRight, .bottomLeft])
            } else {
                VStack(alignment: .leading) {
                    Text(message.text) // TODO: Markdown support
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .foregroundStyle(.primary)
                        .cornerRadius(16, corners: [.topLeft, .topRight, .bottomRight])
                }
                Spacer()
            }
        }
    }
}

struct iOSWelcomeView: View {
    @Binding var showSettings: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 60))
                .foregroundStyle(.blue)
            Text("Welcome to Lumen")
                .font(.title)
                .fontWeight(.bold)
            Text("Select a conversation or start a new one.")
                .foregroundStyle(.secondary)
            
            Button("Open Settings") {
                showSettings = true
            }
            .buttonStyle(.bordered)
        }
    }
}

// Helper for rounded corners
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}
#endif
