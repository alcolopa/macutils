import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var cpuController: CPUStatusItemController?
    private var memoryController: MemoryStatusItemController?
    private var diskController: DiskStatusItemController?
    private var networkController: NetworkStatusItemController?
    private var batteryController: BatteryStatusItemController?
    private var tempController: TemperatureStatusItemController?
    private var displayController: DisplayStatusItemController?
    private var weatherController: WeatherStatusItemController?
    
    private var poller: AdaptivePoller?
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        let prefs = AppPreferences.shared
        
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "jpg"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
        
        let poller = AdaptivePoller()
        self.poller = poller
        
        rebuildControllersInOrder()
        
        var appliedInterval = prefs.passiveInterval
        prefs.onPreferencesChanged = { [weak self, weak poller] in
            if prefs.passiveInterval != appliedInterval {
                appliedInterval = prefs.passiveInterval
                poller?.reconfigure()
            }
            self?.rebuildControllersInOrder()
        }
        
        prefs.onOrderChanged = { [weak self] in
            self?.rebuildControllersInOrder()
        }
        
        poller.onMetricsUpdated = { [weak self] cpuStats, memStats, netStats, diskStats, batStats, _ in
            guard let self = self else { return }
            self.cpuController?.update(stats: cpuStats)
            self.memoryController?.update(stats: memStats)
            self.networkController?.update(stats: netStats)
            self.diskController?.update(stats: diskStats)
            self.batteryController?.update(stats: batStats)
        }
        
        poller.onExtendedMetricsUpdated = { [weak self] tempStats, dispStats in
            guard let self = self else { return }
            self.tempController?.update(stats: tempStats)
            self.displayController?.update(stats: dispStats)
        }
        
        poller.onWeatherUpdated = { [weak self] weatherStats in
            guard let self = self else { return }
            self.weatherController?.update(stats: weatherStats)
        }
        
        poller.start()
        
        setupMainMenu()
        
        if CommandLine.arguments.contains("--preferences") || CommandLine.arguments.contains("--settings") {
            DispatchQueue.main.async {
                PreferencesWindowController.shared.showPreferences()
            }
        }
    }
    
    private func setupMainMenu() {
        // Menu bar accessory apps (LSUIElement=true) do not have a default Main Menu.
        // Without an Edit submenu responding to cut/copy/paste/selectAll:, Cmd+V, Cmd+C, Cmd+A, etc.
        // will not work in text fields (like NSSecureTextField and NSTextField).
        let mainMenu = NSMenu()
        
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit MacMonitor", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(redoItem)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        
        NSApp.mainMenu = mainMenu
    }
    
    private func rebuildControllersInOrder() {
        let prefs = AppPreferences.shared
        let currentPoller = self.poller
        
        // Destroy existing status items cleanly
        cpuController = nil
        memoryController = nil
        diskController = nil
        networkController = nil
        batteryController = nil
        tempController = nil
        displayController = nil
        weatherController = nil
        
        // Instantiate in user's specified metricOrder
        for metric in prefs.metricOrder {
            switch metric {
            case .cpu:
                let cpu = CPUStatusItemController()
                cpu.onPopoverStateChanged = { [weak currentPoller] isShown in
                    currentPoller?.registerPopoverState(isShown: isShown)
                }
                self.cpuController = cpu
            case .memory:
                let mem = MemoryStatusItemController()
                mem.onPopoverStateChanged = { [weak currentPoller] isShown in
                    currentPoller?.registerPopoverState(isShown: isShown)
                }
                self.memoryController = mem
            case .disk:
                let disk = DiskStatusItemController()
                disk.onPopoverStateChanged = { [weak currentPoller] isShown in
                    currentPoller?.registerPopoverState(isShown: isShown)
                }
                self.diskController = disk
            case .network:
                let net = NetworkStatusItemController()
                net.onPopoverStateChanged = { [weak currentPoller] isShown in
                    currentPoller?.registerPopoverState(isShown: isShown)
                }
                self.networkController = net
            case .battery:
                let bat = BatteryStatusItemController()
                bat.onPopoverStateChanged = { [weak currentPoller] isShown in
                    currentPoller?.registerPopoverState(isShown: isShown)
                }
                self.batteryController = bat
            case .temperatures:
                let temp = TemperatureStatusItemController()
                temp.onPopoverStateChanged = { [weak currentPoller] isShown in
                    currentPoller?.registerPopoverState(isShown: isShown)
                }
                self.tempController = temp
            case .displays:
                let disp = DisplayStatusItemController()
                disp.onPopoverStateChanged = { [weak currentPoller] isShown in
                    currentPoller?.registerPopoverState(isShown: isShown)
                }
                self.displayController = disp
            case .weather:
                let weather = WeatherStatusItemController()
                weather.onPopoverStateChanged = { [weak currentPoller] isShown in
                    currentPoller?.registerPopoverState(isShown: isShown)
                }
                weather.onRefreshRequested = { [weak currentPoller] in
                    currentPoller?.refreshWeather()
                }
                self.weatherController = weather
            }
        }
        
        syncItemVisibility()
    }
    
    private func syncItemVisibility() {
        let prefs = AppPreferences.shared
        cpuController?.statusItem.isVisible = prefs.showCPU
        memoryController?.statusItem.isVisible = prefs.showMemory
        diskController?.statusItem.isVisible = prefs.showDisk
        networkController?.statusItem.isVisible = prefs.showNetwork
        batteryController?.statusItem.isVisible = prefs.showBattery
        tempController?.statusItem.isVisible = prefs.showTemperatures
        displayController?.statusItem.isVisible = prefs.showDisplays
        weatherController?.statusItem.isVisible = prefs.showWeather
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        poller?.stop()
    }
}
