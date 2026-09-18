import AppKit

@MainActor
public final class PreferencesMenu: NSObject {
    public static func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "MacMonitor Control")
        let prefs = AppPreferences.shared
        
        // Header
        let titleItem = NSMenuItem(title: "MacMonitor", action: nil, keyEquivalent: "")
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
        
        let quitItem = NSMenuItem(title: "Quit MacMonitor", action: #selector(MenuActionsHandler.quitApp), keyEquivalent: "q")
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
    
    @objc public func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
