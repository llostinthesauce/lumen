import Foundation

public protocol ChatEngine {
    func loadModel(at url: URL, config: InferenceConfig) async throws
    func unloadModel() async
    func updateConfig(_ config: InferenceConfig)
    func stream(messages: [Message]) -> AsyncStream<String>
    func cancel() async
}
