import AppKit

@MainActor
public final class PreferencesMenu: NSObject {
    public static func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "MacUtils Control")
        let prefs = AppPreferences.shared
        
        // Header
        let titleItem = NSMenuItem(title: "MacUtils", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())
        
        // Open Preferences Window
        let prefsItem = NSMenuItem(title: "Settings...", action: #selector(MenuActionsHandler.openSettingsWindow), keyEquivalent: ",")
        prefsItem.target = MenuActionsHandler.shared
        menu.addItem(prefsItem)
        menu.addItem(NSMenuItem.separator())
        
        // Module Toggles based on user order
        for metric in prefs.metricOrder {
            let item = NSMenuItem(title: "Show \(metric.displayName)", action: #selector(MenuActionsHandler.toggleMetric(_:)), keyEquivalent: "")
            item.target = MenuActionsHandler.shared
            item.representedObject = metric
            item.state = prefs.isMetricVisible(metric) ? .on : .off
            menu.addItem(item)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // System Actions
        let activityMonitor = NSMenuItem(title: "Open Activity Monitor", action: #selector(MenuActionsHandler.openActivityMonitor), keyEquivalent: "")
        activityMonitor.target = MenuActionsHandler.shared
        menu.addItem(activityMonitor)
        
        menu.addItem(NSMenuItem.separator())
        
        if let update = MenuActionsHandler.shared.updateItem() { menu.addItem(update); menu.addItem(NSMenuItem.separator()) }
        
        let quitItem = NSMenuItem(title: "Quit MacUtils", action: #selector(MenuActionsHandler.quitApp), keyEquivalent: "q")
        quitItem.target = MenuActionsHandler.shared
        menu.addItem(quitItem)
        
        return menu
    }
}

@MainActor
public final class MenuActionsHandler: NSObject {
    public static let shared = MenuActionsHandler()
    
    @objc public func openSettingsWindow() {
        PreferencesWindowController.shared.showPreferences()
    }
    
    @objc public func toggleMetric(_ sender: NSMenuItem) {
        guard let metric = sender.representedObject as? MetricType else { return }
        let current = AppPreferences.shared.isMetricVisible(metric)
        AppPreferences.shared.setMetricVisible(metric, visible: !current)
    }
    
    @objc public func openActivityMonitor() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
    }
    
    /// "Update to X…" item, only when a newer version was found.
    public func updateItem() -> NSMenuItem? {
        guard let release = UpdateManager.shared.availableRelease else { return nil }
        let item = NSMenuItem(title: "Update to \(release.version)…", action: #selector(openUpdates), keyEquivalent: "")
        item.target = self
        return item
    }
    
    @objc public func openUpdates() {
        PreferencesWindowController.shared.showPreferences(selecting: .general)
    }
    
    @objc public func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
