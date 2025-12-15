import SwiftUI

struct ModelDiscoveryView: View {
    @StateObject private var viewModel = ModelDiscoveryViewModel()
    @Environment(\.dismiss) var dismiss
    var onSelectModel: ((HFModel) -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // Header / Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search HuggingFace Models (e.g. 'mlx-community/llama-3')", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                
                if viewModel.isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(12)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            .padding()
            
            // Results Grid
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                    ForEach(viewModel.searchResults) { model in
                        ModelCard(model: model, onSelect: {
                            onSelectModel?(model)
                        })
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        #if os(macOS)
        .background(Color(nsColor: .windowBackgroundColor))
        #else
        .background(Color(.systemBackground))
        #endif
    }
}

struct ModelCard: View {
    let model: HFModel
    var onSelect: (() -> Void)?
    @State private var isHovering = false
    @Environment(\.openURL) private var openURL
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(model.author ?? "Unknown")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.tags.contains("mlx") {
                    Text("MLX")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .foregroundStyle(.blue)
                        .cornerRadius(4)
                }
            }
            
            HStack(spacing: 12) {
                Label("\(model.downloads)", systemImage: "arrow.down.circle")
                Label("\(model.likes)", systemImage: "heart")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            
            Spacer()
            
            HStack {
                Button(action: {
                    if let url = URL(string: "https://huggingface.co/\(model.modelId)") {
                        openURL(url)
                    }
                }) {
                    Text("View on HF")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                if let onSelect {
                    Button(action: onSelect) {
                        Text("Download")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .padding(12)
#if os(macOS)
        .background(Color(nsColor: .controlBackgroundColor))
#else
        .background(Color(.secondarySystemBackground))
        #endif
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(isHovering ? 0.2 : 0.05), lineWidth: 1)
        )
        .shadow(color: .black.opacity(isHovering ? 0.1 : 0), radius: 4, x: 0, y: 2)
        .onHover { isHovering = $0 }
    }
}
