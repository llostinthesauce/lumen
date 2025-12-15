import Foundation
#if os(macOS)
import AppKit
import Carbon

public final class HotKeyManager {
    public static let shared = HotKeyManager()
    
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    public var onKeyDown: (() -> Void)?
    
    private init() {}
    
    public func register(key: Int, modifiers: Int) {
        unregister()
        
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType("LUMN".asUInt32)
        hotKeyID.id = 1
        
        let status = RegisterEventHotKey(
            UInt32(key),
            UInt32(modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if status != noErr {
            print("HotKeyManager: Failed to register hotkey. Status: \(status)")
            return
        }
        
        installEventHandler()
        print("HotKeyManager: Registered hotkey")
    }
    
    public func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }
    
    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        
        let handler: EventHandlerUPP = { _, _, _ in
            HotKeyManager.shared.onKeyDown?()
            return noErr
        }
        
        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            nil,
            &eventHandler
        )
    }
}

// MARK: - Helper Extensions

private extension String {
    var asUInt32: UInt32 {
        var result: UInt32 = 0
        for char in self.utf8 {
            result = (result << 8) | UInt32(char)
        }
        return result
    }
}
#else
public final class HotKeyManager {
    public static let shared = HotKeyManager()
    public var onKeyDown: (() -> Void)?
    
    private init() {}
    
    public func register(key: Int, modifiers: Int) {}
    public func unregister() {}
}
#endif
