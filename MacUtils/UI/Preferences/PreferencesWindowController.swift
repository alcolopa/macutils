import AppKit

private final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
public final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    public static let shared = PreferencesWindowController()
    
    private let split = PreferencesSplitViewController()
    
    private init() {
        let window = KeyWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "MacUtils Settings"
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.collectionBehavior = [.moveToActiveSpace, .participatesInCycle]
        window.minSize = NSSize(width: 800, height: 520)
        super.init(window: window)
        
        window.delegate = self
        window.contentViewController = split
        // Assigning a contentViewController resizes the window to the view size; restore it.
        window.setContentSize(NSSize(width: 900, height: 680))
        window.center()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func showPreferences(selecting page: PreferencesPage? = nil) {
        // MacUtils stays a menu bar app (no Dock icon) while Settings is open. Switching to a regular app made macOS
        // move the menu bar items to the Settings window's display, so monitors on other displays stopped opening.
        guard let window = self.window else { return }
        if let page { split.select(page) }
        
        if !window.isVisible, let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let size = window.frame.size
            window.setFrameOrigin(NSPoint(x: screenFrame.midX - size.width / 2, y: screenFrame.midY - size.height / 2))
        }
        
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
    
    // MARK: - NSWindowDelegate
    public func windowWillClose(_ notification: Notification) {}
}
