import Foundation
#if os(macOS)
import AppKit
import SwiftUI
import Carbon

public final class SpotlightPanel: NSPanel {
    public init(contentRect: NSRect, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: backing, defer: flag)
        
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isFloatingPanel = true
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = true
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isOpaque = false
        
        // Center on screen initially
        self.center()
    }
    
    public override var canBecomeKey: Bool {
        return true
    }
    
    public override var canBecomeMain: Bool {
        return true
    }
}

public class SpotlightManager: NSObject {
    private var panel: SpotlightPanel?
    private let state: AppState
    private let sessionController: ChatSessionController
    
    public init(state: AppState, sessionController: ChatSessionController) {
        self.state = state
        self.sessionController = sessionController
        super.init()
        setupPanel()
        setupHotKey()
    }
    
    private func setupPanel() {
        // Create the view with a callback to close the panel
        let contentView = SpotlightView(
            state: state,
            sessionController: sessionController,
            onClose: { [weak self] in self?.closePanel() }
        )
        
        let panel = SpotlightPanel(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 600), // Initial size
            backing: .buffered,
            defer: false
        )
        
        // Hosting view needs to be transparent to support the rounded corners of the SwiftUI view
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        
        panel.contentView = hostingView
        self.panel = panel
    }
    
    private func setupHotKey() {
        // Register Command + Shift + K
        // kVK_ANSI_K = 40
        // cmdKey (256) + shiftKey (512) = 768
        
        HotKeyManager.shared.onKeyDown = { [weak self] in
            DispatchQueue.main.async {
                self?.togglePanel()
            }
        }
        
        HotKeyManager.shared.register(key: 40, modifiers: 768)
    }
    
    public func togglePanel() {
        guard let panel = panel else { return }
        
        if panel.isVisible {
            closePanel()
        } else {
            openPanel()
        }
    }
    
    public func openPanel() {
        guard let panel = panel else { return }
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    public func closePanel() {
        panel?.orderOut(nil)
    }
}
#else
public final class SpotlightPanel {}
public class SpotlightManager {}
#endif
