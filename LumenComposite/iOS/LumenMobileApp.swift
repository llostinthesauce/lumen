import SwiftUI

#if os(iOS)
@main
struct LumenMobileApp: App {
    @StateObject private var state: AppState
    @StateObject private var sessionController: ChatSessionController

    init() {
        // Ensure the Models directory exists on first launch
        ModelStorage.shared.ensureModelsDirExists()
        // Copy any bundled models into place if they aren't already installed
        ModelStorage.shared.installBundledModelsIfNeeded()
        
        let engine = MultiEngine()
        let appState = AppState(engine: engine)
        _state = StateObject(wrappedValue: appState)
        _sessionController = StateObject(wrappedValue: ChatSessionController(state: appState))
    }

    var body: some Scene {
        WindowGroup {
            // Use the shared RootView for a unified UI across platforms
            RootView(state: state, sessionController: sessionController)
        }
    }
}
#endif
