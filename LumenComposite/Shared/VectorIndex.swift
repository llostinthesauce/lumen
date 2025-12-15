import Foundation
import Combine

public struct EmbeddedChunk: Codable, Identifiable {
    public let id: UUID
    public let chunkID: UUID
    public let documentID: UUID
    public let index: Int
    public let vector: [Float]
    
    public init(
        id: UUID = UUID(),
        chunkID: UUID,
        documentID: UUID,
        index: Int,
        vector: [Float]
    ) {
        self.id = id
        self.chunkID = chunkID
        self.documentID = documentID
        self.index = index
        self.vector = vector
    }
}

public final class VectorIndex: ObservableObject {
    @Published public private(set) var entries: [EmbeddedChunk] = []
    public private(set) var dimension: Int = 0
    
    private struct Snapshot: Codable {
        let dimension: Int
        let entries: [EmbeddedChunk]
    }
    
    public init() {}
    
    public func load(from url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        guard let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        dimension = snapshot.dimension
        entries = snapshot.entries
    }
    
    public func save(to url: URL) {
        let snapshot = Snapshot(dimension: dimension, entries: entries)
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: url, options: [.atomic])
        }
    }
    
    public func clear() {
        entries.removeAll()
        dimension = 0
    }
    
    public func addEntries(_ newEntries: [EmbeddedChunk]) {
        guard !newEntries.isEmpty else { return }
        if dimension == 0, let vector = newEntries.first?.vector {
            dimension = vector.count
        }
        entries.append(contentsOf: newEntries.filter { $0.vector.count == dimension && dimension > 0 })
    }
    
    public func replaceEntries(for documentID: UUID, with newEntries: [EmbeddedChunk]) {
        entries.removeAll { $0.documentID == documentID }
        addEntries(newEntries)
    }
    
    public func removeEntries(for documentID: UUID) {
        entries.removeAll { $0.documentID == documentID }
        if entries.isEmpty {
            dimension = 0
        }
    }
    
    public func query(vector: [Float], topK: Int) -> [EmbeddedChunk] {
        guard dimension > 0, vector.count == dimension else { return [] }
        let scored = entries.map { entry -> (EmbeddedChunk, Float) in
            (entry, cosine(vector, entry.vector))
        }
        return scored
            .sorted(by: { $0.1 > $1.1 })
            .prefix(topK)
            .map { $0.0 }
    }
    
    private func cosine(_ a: [Float], _ b: [Float]) -> Float {
        var dot: Float = 0
        var na: Float = 0
        var nb: Float = 0
        for i in 0..<dimension {
            let x = a[i]
            let y = b[i]
            dot += x * y
            na += x * x
            nb += y * y
        }
        let denom = sqrt(na) * sqrt(nb)
        return denom > 0 ? dot / denom : 0
    }
}
