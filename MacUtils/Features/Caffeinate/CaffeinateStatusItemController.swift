import AppKit

/// Menu bar cup. Click toggles Caffeinate using the default duration; right-click (or ⌃-click) opens the menu.
@MainActor
public final class CaffeinateStatusItemController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let manager = CaffeinateManager.shared
    private var countdownTimer: Timer?
    
    public override init() {
        super.init()
        NotificationCenter.default.addObserver(forName: CaffeinateManager.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }
    
    /// Creates the menu bar item. Newer items appear to the left of older ones, so callers install right to left.
    public func install() {
        removeFromStatusBar()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let button = item.button {
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeft
        }
        refresh()
        syncVisibility()
    }
    
    public func syncVisibility() {
        statusItem?.isVisible = AppPreferences.shared.showCaffeinate
    }
    
    public func removeFromStatusBar() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
        statusItem = nil
    }
    
    private func refresh() {
        let active = manager.isActive
        let image = NSImage(systemSymbolName: active ? "cup.and.saucer.fill" : "cup.and.saucer", accessibilityDescription: "Caffeinate")
        image?.isTemplate = true
        statusItem?.button?.image = image
        statusItem?.button?.toolTip = active
            ? "Caffeinate is on. Click to turn off, right-click for options."
            : "Caffeinate is off. Click to keep your Mac awake, right-click for options."
        updateTitle()
        countdownTimer?.invalidate()
        countdownTimer = nil
        if active, manager.endDate != nil {
            countdownTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateTitle() }
            }
        }
    }
    
    private func updateTitle() {
        guard manager.isActive, let end = manager.endDate else {
            statusItem?.button?.title = ""
            return
        }
        let minutes = max(1, Int((end.timeIntervalSinceNow / 60).rounded(.up)))
        let text = minutes >= 60 ? "\(minutes / 60)h\(minutes % 60 == 0 ? "" : " \(minutes % 60)m")" : "\(minutes)m"
        statusItem?.button?.attributedTitle = NSAttributedString(string: " " + text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        ])
    }
    
    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if wantsMenu {
            let menu = NSMenu()
            menu.delegate = self
            statusItem?.menu = menu
            sender.performClick(nil)
            statusItem?.menu = nil
        } else if manager.isActive {
            manager.stop()
        } else {
            manager.startDefault()
        }
    }
    
    // MARK: - NSMenuDelegate
    
    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        
        let status: String
        if !manager.isActive {
            status = "Caffeinate is off"
        } else if let end = manager.endDate {
            let f = DateFormatter()
            f.timeStyle = .short
            status = "Awake until \(f.string(from: end))"
        } else {
            status = "Keeping your Mac awake"
        }
        let header = NSMenuItem(title: status, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        
        if manager.isActive {
            let off = NSMenuItem(title: "Turn Off", action: #selector(turnOff), keyEquivalent: "")
            off.target = self
            menu.addItem(off)
        }
        menu.addItem(.separator())
        
        let caption = NSMenuItem(title: manager.isActive ? "Restart for" : "Keep awake for", action: nil, keyEquivalent: "")
        caption.isEnabled = false
        menu.addItem(caption)
        for (index, preset) in CaffeinateManager.presets.enumerated() {
            let item = NSMenuItem(title: preset.title, action: #selector(startSession(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.indentationLevel = 1
            menu.addItem(item)
        }
        
        menu.addItem(.separator())
        let display = NSMenuItem(title: "Also Keep Display Awake", action: #selector(toggleDisplay), keyEquivalent: "")
        display.target = self
        display.state = AppPreferences.shared.caffeinateKeepDisplayAwake ? .on : .off
        menu.addItem(display)
        
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Caffeinate Settings...", action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        if let update = MenuActionsHandler.shared.updateItem() { menu.addItem(.separator()); menu.addItem(update) }
        let quit = NSMenuItem(title: "Quit MacUtils", action: #selector(MenuActionsHandler.quitApp), keyEquivalent: "q")
        quit.target = MenuActionsHandler.shared
        menu.addItem(quit)
    }
    
    @objc private func openSettings() {
        PreferencesWindowController.shared.showPreferences(selecting: .caffeinate)
    }
    
    @objc private func startSession(_ sender: NSMenuItem) {
        let duration = CaffeinateManager.presets[sender.tag].seconds
        manager.start(duration: duration, keepDisplayAwake: AppPreferences.shared.caffeinateKeepDisplayAwake)
    }
    
    @objc private func turnOff() { manager.stop() }
    
    @objc private func toggleDisplay() {
        let prefs = AppPreferences.shared
        prefs.caffeinateKeepDisplayAwake.toggle()
        // Apply to the running session, keeping its remaining time.
        if manager.isActive {
            let remaining = manager.endDate.map { max(1, $0.timeIntervalSinceNow) }
            manager.start(duration: remaining, keepDisplayAwake: prefs.caffeinateKeepDisplayAwake)
        }
    }
}
