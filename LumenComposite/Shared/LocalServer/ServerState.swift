import Foundation
import Combine

@MainActor
class ServerState: ObservableObject {
    static let shared = ServerState()
    
    @Published var isRunning = false
    @Published var port: UInt16 = 1234
    @Published var logs: [String] = []
    @Published var error: String?
    @Published var isEnabled: Bool = UserDefaults.standard.bool(forKey: "apiServer.enabled") {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "apiServer.enabled")
            if !isEnabled {
                stop()
            }
        }
    }
    
    private var server: APIServer?
    
    private init() {}
    
    func start(with state: AppState) {
        guard isEnabled else {
            log("API server is disabled. Enable it before starting.")
            return
        }
        guard !isRunning else { return }
        let server = APIServer(port: port, state: state)
        do {
            try server.start()
            self.server = server
            isRunning = true
            log("Server started on port \(port)")
        } catch {
            self.error = error.localizedDescription
            log("Failed to start server: \(error.localizedDescription)")
        }
    }
    
    func stop() {
        server?.stop()
        server = nil
        isRunning = false
        log("Server stopped")
    }
    
    func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logs.append("[\(timestamp)] \(message)")
        if logs.count > 1000 {
            logs.removeFirst()
        }
    }
}
