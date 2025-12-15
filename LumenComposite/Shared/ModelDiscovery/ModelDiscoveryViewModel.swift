import Foundation
import Combine
import SwiftUI

// MARK: - HuggingFace API Models

struct HFModel: Codable, Identifiable {
    let id: String
    let modelId: String
    let author: String?
    let likes: Int
    let downloads: Int
    let tags: [String]
    let pipeline_tag: String?
    let library_name: String?
    
    var name: String {
        modelId.components(separatedBy: "/").last ?? modelId
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case modelId = "modelId"
        case author
        case likes
        case downloads
        case tags
        case pipeline_tag
        case library_name
    }
}

// MARK: - ViewModel

@MainActor
class ModelDiscoveryViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var searchResults: [HFModel] = []
    @Published var isSearching = false
    @Published var errorMessage: String?
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        $searchText
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] text in
                guard let self = self else { return }
                if !text.isEmpty {
                    Task {
                        await self.searchModels(query: text)
                    }
                } else {
                    self.searchResults = []
                }
            }
            .store(in: &cancellables)
    }
    
    func searchModels(query: String) async {
        guard !query.isEmpty else { return }
        
        isSearching = true
        errorMessage = nil
        
        // Filter for MLX compatible models or GGUF if we support conversion (for now focus on MLX)
        // We can search for "mlx" tag or just general search and filter client side
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://huggingface.co/api/models?search=\(encodedQuery)&limit=20&full=true&config=true"
        
        guard let url = URL(string: urlString) else {
            isSearching = false
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decodedModels = try JSONDecoder().decode([HFModel].self, from: data)
            
            // Filter for likely compatible models (mlx, or just show all and let user decide)
            // For now, let's show all but highlight MLX ones
            self.searchResults = decodedModels.sorted { $0.likes > $1.likes }
            self.isSearching = false
        } catch {
            print("Search error: \(error)")
            self.errorMessage = "Failed to search models: \(error.localizedDescription)"
            self.isSearching = false
        }
    }
}
