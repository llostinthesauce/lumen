import Foundation

enum HuggingFaceDownloader {
    struct DownloadError: Error {
        let message: String
    }
    
    static func downloadRepository(modelId: String, targetFolderName: String? = nil, progressHandler: @escaping (Double, String) -> Void) async throws {
        // Fetch repo tree to identify relevant files
        let apiURL = URL(string: "https://huggingface.co/api/models/\(modelId)")!
        let (data, _) = try await URLSession.shared.data(from: apiURL)
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let siblings = json["siblings"] as? [[String: Any]]
        else {
            throw DownloadError(message: "Failed to parse model metadata.")
        }
        
        // Collect relevant files (config/tokenizer/safetensors)
        let allowed = Set(["config.json", "tokenizer.json", "tokenizer_config.json", "model.safetensors.index.json"])
        var files: [String] = []
        for sib in siblings {
            if let rfilename = sib["rfilename"] as? String {
                if allowed.contains(rfilename) || rfilename.hasSuffix(".safetensors") {
                    files.append(rfilename)
                }
            }
        }
        guard !files.isEmpty else {
            throw DownloadError(message: "No MLX-compatible files found.")
        }
        
        // Ensure target folder
        let folderName = targetFolderName ?? modelId
        let target = ModelStorage.shared.modelsURL.appendingPathComponent(folderName, isDirectory: true)
        let fm = FileManager.default
        if fm.fileExists(atPath: target.path) {
            try? fm.removeItem(at: target)
        }
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        
        // Download sequentially to show progress
        let total = Double(files.count)
        for (idx, file) in files.enumerated() {
            let pct = Double(idx) / total
            progressHandler(pct, "Downloading \(file)…")
            let url = URL(string: "https://huggingface.co/\(modelId)/resolve/main/\(file)")!
            let dest = target.appendingPathComponent(file)
            let (fdata, _) = try await URLSession.shared.data(from: url)
            try fdata.write(to: dest)
        }
        progressHandler(1.0, "Download complete.")
    }
}
