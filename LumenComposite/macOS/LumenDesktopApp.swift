import SwiftUI

#if os(macOS)
@main
struct LumenDesktopApp: App {
    @StateObject private var state: AppState
    @StateObject private var sessionController: ChatSessionController
    @NSApplicationDelegateAdaptor(LumenAppDelegate.self) var appDelegate

    init() {
        // Directory creation is now handled lazily or by user action
        let engine = MlxEngine()
        let appState = AppState(engine: engine)
        _state = StateObject(wrappedValue: appState)
        _sessionController = StateObject(wrappedValue: ChatSessionController(state: appState))
    }

    var body: some Scene {
        WindowGroup {
            // Use the shared RootView for a unified UI across platforms
            RootView(state: state, sessionController: sessionController)
                .onAppear {
                    appDelegate.configure(state: state, sessionController: sessionController)
                }
        }
        .defaultSize(width: 1200, height: 800)
        .windowStyle(.hiddenTitleBar)
    }
}

class LumenAppDelegate: NSObject, NSApplicationDelegate {
    var spotlightManager: SpotlightManager?
    
    func configure(state: AppState, sessionController: ChatSessionController) {
        if spotlightManager == nil {
            spotlightManager = SpotlightManager(state: state, sessionController: sessionController)
        }
    }
}
#endif
