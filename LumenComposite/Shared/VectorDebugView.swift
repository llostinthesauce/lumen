import SwiftUI

struct VectorDebugView: View {
    @ObservedObject var state: AppState
    @State private var chunks: [VectorDocumentChunk] = []
    @State private var searchText = ""
    @State private var isLoading = false
    
    var filteredChunks: [VectorDocumentChunk] {
        if searchText.isEmpty {
            return chunks
        }
        return chunks.filter { chunk in
            chunk.sourceID.localizedCaseInsensitiveContains(searchText) ||
            chunk.content.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var groupedChunks: [String: [VectorDocumentChunk]] {
        Dictionary(grouping: filteredChunks, by: { $0.sourceID })
    }
    
    var body: some View {
        List {
            if isLoading {
                ProgressView("Loading vectors...")
            } else if chunks.isEmpty {
                Text("No vectors found in database.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(groupedChunks.keys.sorted(), id: \.self) { sourceID in
                    Section(header: Text(sourceID).font(.caption).lineLimit(1)) {
                        if let docChunks = groupedChunks[sourceID] {
                            ForEach(docChunks.sorted(by: { $0.chunkIndex < $1.chunkIndex }), id: \.chunkIndex) { chunk in
                                ChunkRow(chunk: chunk)
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search source or content")
        .navigationTitle("Vector Database Debug")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            isLoading = true
            // Load off main thread
            let allChunks = await Task.detached {
                return await state.debugGetAllChunks()
            }.value
            await MainActor.run {
                self.chunks = allChunks
                self.isLoading = false
            }
        }

        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack {
                    Text("\(chunks.count) chunks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Button(role: .destructive) {
                        showClearConfirmation = true
                    } label: {
                        Label("Clear Database", systemImage: "trash")
                    }
                }
            }
        }
        .alert("Clear Vector Database?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                state.purgeVectorDatabase()
                // Refresh the list (it should be empty now)
                chunks = []
            }
        } message: {
            Text("This will remove all indexed documents and embeddings. You will need to re-index your content to use RAG features.")
        }
    }
    
    @State private var showClearConfirmation = false
}

struct ChunkRow: View {
    let chunk: VectorDocumentChunk
    @State private var isExpanded = false
    @State private var isCopied = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Chunk #\(chunk.chunkIndex)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
                
                Spacer()
                
                Text("\(chunk.embedding.count) dims")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Text(chunk.content)
                .font(.system(.body, design: .monospaced))
                .lineLimit(isExpanded ? nil : 3)
                .onTapGesture {
                    withAnimation {
                        isExpanded.toggle()
                    }
                }
            
            if isExpanded {
                HStack {
                    Button(action: {
                        let json = (try? JSONEncoder().encode(chunk.embedding)) ?? Data()
                        let str = String(data: json, encoding: .utf8) ?? "[]"
                        copyToClipboard(str)
                        isCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            isCopied = false
                        }
                    }) {
                        Label(isCopied ? "Copied Vector" : "Copy Vector JSON", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}
