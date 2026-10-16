import AppKit
import ApplicationServices

/// Puts a history item on the clipboard and sends ⌘V to the frontmost app (which needs Accessibility access).
@MainActor
public enum PasteService {
    private static let promptedKey = "accessibilityPrompted"
    
    public static var hasAccess: Bool { AXIsProcessTrusted() }
    
    public static func requestAccess() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }
    
    public static func openAccessibilitySettings() {
        requestAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Returns false when only the clipboard could be set (no Accessibility access), so the caller can tell the user.
    @discardableResult
    public static func paste(_ item: ClipboardItem, after delay: TimeInterval = 0.06) -> Bool {
        ClipboardStore.shared.writeToPasteboard(item)
        guard hasAccess else {
            if !UserDefaults.standard.bool(forKey: promptedKey) {
                UserDefaults.standard.set(true, forKey: promptedKey)
                requestAccess()
            }
            return false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { postPaste() }
        return true
    }
    
    private static func postPaste() {
        let source = CGEventSource(stateID: .hidSystemState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}
