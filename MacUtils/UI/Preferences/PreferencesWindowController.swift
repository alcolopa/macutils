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
        window.title = "MacUtils Preferences"
        window.center()
        window.isReleasedWhenClosed = false
        window.showsToolbarButton = false
        window.collectionBehavior = [.moveToActiveSpace, .participatesInCycle]
        window.minSize = NSSize(width: 680, height: 800)
        window.maxSize = NSSize(width: 680, height: 800) // Keep window size stable across tabs
        super.init(window: window)
        
        window.delegate = self
        let tabVC = PreferencesTabViewController()
        tabVC.transitionOptions = [] // Instant tab switch without layout resizing animations
        window.contentViewController = tabVC
        // Assigning a contentViewController resizes the window to the first tab's view size; restore it.
        window.setContentSize(NSSize(width: 680, height: 800))
        window.center()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func showPreferences(selecting tabIndex: Int? = nil) {
        // Temporarily elevate to .regular application policy so the window can receive full keyboard focus,
        // text cursor, and keyboard shortcut events even though MacUtils is a menu bar app (LSUIElement).
        NSApp.setActivationPolicy(.regular)
        
        guard let window = self.window else { return }
        if let idx = tabIndex, let tabVC = window.contentViewController as? PreferencesTabViewController {
            if idx >= 0 && idx < tabVC.tabViewItems.count {
                tabVC.selectedTabViewItemIndex = idx
            }
        }
        
        // Move window to the currently active screen/space
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowSize = window.frame.size
            let x = screenFrame.origin.x + (screenFrame.width - windowSize.width) / 2
            let y = screenFrame.origin.y + (screenFrame.height - windowSize.height) / 2
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
    
    // MARK: - NSWindowDelegate
    public func windowWillClose(_ notification: Notification) {
        // Return to accessory policy when preferences window closes so MacUtils does not remain in the Dock
        NSApp.setActivationPolicy(.accessory)
    }
}
