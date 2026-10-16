import AppKit

@MainActor
public final class CaffeinateStatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let manager = CaffeinateManager.shared
    
    private static let durations: [(String, TimeInterval?)] = [
        ("15 minutes", 15 * 60), ("30 minutes", 30 * 60), ("1 hour", 3600),
        ("2 hours", 2 * 3600), ("4 hours", 4 * 3600), ("8 hours", 8 * 3600),
        ("Until I turn it off", nil)
    ]
    
    public override init() {
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        manager.onChange = { [weak self] in self?.refreshIcon() }
        refreshIcon()
        syncVisibility()
    }
    
    public func syncVisibility() {
        statusItem.isVisible = AppPreferences.shared.showCaffeinate
    }
    
    public func removeFromStatusBar() {
        NSStatusBar.system.removeStatusItem(statusItem)
    }
    
    private func refreshIcon() {
        let active = manager.isActive
        let name = active ? "cup.and.saucer.fill" : "cup.and.saucer"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Caffeinate")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = active ? "Caffeinate: keeping your Mac awake" : "Caffeinate: off"
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
            status = "Keeping your Mac awake until \(f.string(from: end))"
        } else {
            status = "Keeping your Mac awake"
        }
        let header = NSMenuItem(title: status, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        
        if manager.isActive {
            let off = NSMenuItem(title: "Turn Off", action: #selector(turnOff), keyEquivalent: "")
            off.target = self
            menu.addItem(off)
            menu.addItem(.separator())
        }
        
        let sub = NSMenuItem(title: manager.isActive ? "Restart for…" : "Keep Awake For…", action: nil, keyEquivalent: "")
        let subMenu = NSMenu()
        for (index, entry) in Self.durations.enumerated() {
            let item = NSMenuItem(title: entry.0, action: #selector(startSession(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            subMenu.addItem(item)
        }
        sub.submenu = subMenu
        menu.addItem(sub)
        
        let display = NSMenuItem(title: "Also Keep Display Awake", action: #selector(toggleDisplay), keyEquivalent: "")
        display.target = self
        display.state = AppPreferences.shared.caffeinateKeepDisplayAwake ? .on : .off
        menu.addItem(display)
        
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings...", action: #selector(MenuActionsHandler.openSettingsWindow), keyEquivalent: ",")
        settings.target = MenuActionsHandler.shared
        menu.addItem(settings)
        let quit = NSMenuItem(title: "Quit MacUtils", action: #selector(MenuActionsHandler.quitApp), keyEquivalent: "q")
        quit.target = MenuActionsHandler.shared
        menu.addItem(quit)
    }
    
    @objc private func startSession(_ sender: NSMenuItem) {
        let duration = Self.durations[sender.tag].1
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
