import AppKit

private final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
public final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    public static let shared = PreferencesWindowController()
    
    private init() {
        let window = KeyWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 800),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MacMonitor Preferences"
        window.center()
        window.isReleasedWhenClosed = false
        window.showsToolbarButton = false
        window.minSize = NSSize(width: 680, height: 800)
        window.maxSize = NSSize(width: 680, height: 800) // Keep window size stable across tabs
        super.init(window: window)
        
        window.delegate = self
        let tabVC = PreferencesTabViewController()
        tabVC.transitionOptions = [] // Instant tab switch without layout resizing animations
        window.contentViewController = tabVC
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func showPreferences(selecting tabIndex: Int? = nil) {
        // Temporarily elevate to .regular application policy so the window can receive full keyboard focus,
        // text cursor, and keyboard shortcut events even though MacMonitor is a menu bar app (LSUIElement).
        NSApp.setActivationPolicy(.regular)
        
        guard let window = self.window else { return }
        if let idx = tabIndex, let tabVC = window.contentViewController as? PreferencesTabViewController {
            if idx >= 0 && idx < tabVC.tabViewItems.count {
                tabVC.selectedTabViewItemIndex = idx
            }
        }
        
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
    
    // MARK: - NSWindowDelegate
    public func windowWillClose(_ notification: Notification) {
        // Return to accessory policy when preferences window closes so MacMonitor does not remain in the Dock
        NSApp.setActivationPolicy(.accessory)
    }
}
