import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var cpuController: CPUStatusItemController?
    private var memoryController: MemoryStatusItemController?
    private var diskController: DiskStatusItemController?
    private var networkController: NetworkStatusItemController?
    private var tempController: TemperatureStatusItemController?
    private var weatherController: WeatherStatusItemController?
    private var caffeinateController: CaffeinateStatusItemController?
    private var clipboardController: ClipboardStatusItemController?
    
    /// Fixed pool of NSStatusItems corresponding to slot positions in the status bar.
    /// Metric reordering reuses these slots; moving an entire group recreates them.
    private var statusItemSlots: [NSStatusItem] = []
    
    private var poller: AdaptivePoller?
    /// When a popover last opened. Activation and Space notifications that arrive right after a click
    /// (e.g. clicking a monitor on a different display than the Settings window) must not close it.
    private var lastPopoverShown = Date.distantPast
    
    /// Bundle.module traps if the resource bundle isn't at the .app root, so look in the
    /// places it can actually live (Contents/Resources in the app, next to the binary for `swift run`).
    private static func loadDevIcon() -> NSImage? {
        let name = "MacUtils_MacUtils.bundle"
        let dirs = [Bundle.main.resourceURL, Bundle.main.bundleURL, Bundle.main.executableURL?.deletingLastPathComponent()]
        for dir in dirs.compactMap({ $0 }) {
            if let bundle = Bundle(url: dir.appendingPathComponent(name)),
               let url = bundle.url(forResource: "AppIcon", withExtension: "png"),
               let icon = NSImage(contentsOf: url) {
                return icon
            }
        }
        return nil
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let prefs = AppPreferences.shared
        
        if let icon = Self.loadDevIcon() {
            NSApp.applicationIconImage = icon
        }
        
        let poller = AdaptivePoller()
        self.poller = poller
        
        setupControllers()
        caffeinateController = CaffeinateStatusItemController()
        clipboardController = ClipboardStatusItemController()
        applyBarBlockOrder()
        syncClipboardManager()
        
        var appliedInterval = prefs.passiveInterval
        var appliedWeather = "\(prefs.weatherUpdateInterval)|\(prefs.weatherForecastMode.rawValue)"
        prefs.onPreferencesChanged = { [weak self, weak poller] in
            let weatherNow = "\(prefs.weatherUpdateInterval)|\(prefs.weatherForecastMode.rawValue)"
            if prefs.passiveInterval != appliedInterval || weatherNow != appliedWeather {
                appliedInterval = prefs.passiveInterval
                appliedWeather = weatherNow
                poller?.reconfigure()   // restarts the weather timer, which also refetches right away
            }
            // Update in place (no destroy/recreate) so the widgets don't blink while settings change.
            self?.refreshControllers()
            self?.caffeinateController?.syncVisibility()
            self?.syncClipboardManager()
            self?.clipboardController?.syncVisibility()
        }
        
        prefs.onOrderChanged = { [weak self] in
            // Instantly rearrange controllers into status bar slots without destroying/recreating items
            self?.applyOrderToSlots()
        }
        
        prefs.onBlockOrderChanged = { [weak self] in
            self?.applyBarBlockOrder()
        }
        
        poller.onMetricsUpdated = { [weak self] cpuStats, memStats, netStats, diskStats, _ in
            guard let self = self else { return }
            self.cpuController?.update(stats: cpuStats)
            self.memoryController?.update(stats: memStats)
            self.networkController?.update(stats: netStats)
            self.diskController?.update(stats: diskStats)
        }
        
        poller.onExtendedMetricsUpdated = { [weak self] tempStats in
            guard let self = self else { return }
            self.tempController?.update(stats: tempStats)
        }
        
        poller.onWeatherUpdated = { [weak self] weatherStats in
            guard let self = self else { return }
            self.weatherController?.update(stats: weatherStats)
        }
        
        poller.start()
        
        setupMainMenu()
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { UpdateManager.shared.checkInBackgroundIfDue() }
        
        NotificationCenter.default.addObserver(forName: NSPopover.willShowNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.lastPopoverShown = Date() }
        }
        
        // Close any open popover when the user switches Spaces, so it can be reopened on the new one.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeAllPopovers() }
        }

        // Close open popovers when another application becomes active or when this app loses focus.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            // Clicking a monitor while Settings is open activates MacUtils itself; that must not close the popover it just opened.
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            MainActor.assumeIsolated { self?.closeAllPopovers() }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeAllPopovers() }
        }

        // Catch clicks outside the app/popover that switch focus to other windows/apps.
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.closeAllPopovers()
            }
        }
        
        if CommandLine.arguments.contains("--preferences") || CommandLine.arguments.contains("--settings") {
            DispatchQueue.main.async {
                PreferencesWindowController.shared.showPreferences()
            }
        }
    }
    
    private func syncClipboardManager() {
        if AppPreferences.shared.clipboardEnabled {
            ClipboardPicker.shared.start()
        } else {
            ClipboardPicker.shared.stop()
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
        // Cmd+Q only closes the front window (e.g. Preferences); the app keeps running in the menu bar.
        // Quitting is still available from the status item menu.
        appMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "q")
        appMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
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
    
    private func setupControllers() {
        let currentPoller = self.poller
        
        let cpu = CPUStatusItemController()
        cpu.onPopoverStateChanged = { [weak currentPoller] isShown in
            currentPoller?.registerPopoverState(for: .cpu, isShown: isShown)
        }
        self.cpuController = cpu
        
        let mem = MemoryStatusItemController()
        mem.onPopoverStateChanged = { [weak currentPoller] isShown in
            currentPoller?.registerPopoverState(for: .memory, isShown: isShown)
        }
        self.memoryController = mem
        
        let disk = DiskStatusItemController()
        disk.onPopoverStateChanged = { [weak currentPoller] isShown in
            currentPoller?.registerPopoverState(for: .disk, isShown: isShown)
        }
        self.diskController = disk
        
        let net = NetworkStatusItemController()
        net.onPopoverStateChanged = { [weak currentPoller] isShown in
            currentPoller?.registerPopoverState(for: .network, isShown: isShown)
        }
        self.networkController = net
        
        let temp = TemperatureStatusItemController()
        temp.onPopoverStateChanged = { [weak currentPoller] isShown in
            currentPoller?.registerPopoverState(for: .temperatures, isShown: isShown)
        }
        self.tempController = temp
        
        let weather = WeatherStatusItemController()
        weather.onPopoverStateChanged = { [weak currentPoller] isShown in
            currentPoller?.registerPopoverState(for: .weather, isShown: isShown)
        }
        weather.onRefreshRequested = { [weak currentPoller] in
            currentPoller?.refreshWeather()
        }
        self.weatherController = weather
        
    }
    
    /// macOS puts each new status item to the left of the existing ones, so the groups are (re)created
    /// right to left. Only runs at launch and when the user moves a group.
    private func applyBarBlockOrder() {
        caffeinateController?.removeFromStatusBar()
        clipboardController?.removeFromStatusBar()
        for slot in statusItemSlots { NSStatusBar.system.removeStatusItem(slot) }
        statusItemSlots.removeAll()
        
        for block in AppPreferences.shared.barBlockOrder.reversed() {
            switch block {
            case .caffeinate:
                caffeinateController?.install()
            case .clipboard:
                clipboardController?.install()
            case .monitors:
                statusItemSlots = (0..<MetricType.allCases.count).map { _ in
                    NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                }.reversed()
                applyOrderToSlots()
            }
        }
    }
    
    private func controller(for metric: MetricType) -> MetricStatusItemControlling? {
        switch metric {
        case .cpu: return cpuController
        case .memory: return memoryController
        case .disk: return diskController
        case .network: return networkController
        case .temperatures: return tempController
        case .weather: return weatherController
        }
    }
    
    private func applyOrderToSlots() {
        let prefs = AppPreferences.shared
        let order = prefs.metricOrder
        
        for (index, metric) in order.enumerated() {
            guard index < statusItemSlots.count,
                  let ctrl = controller(for: metric) else { continue }
            let slot = statusItemSlots[index]
            ctrl.attach(to: slot)
            slot.isVisible = prefs.isMetricVisible(metric)
        }
    }
    
    private func closeAllPopovers() {
        guard Date().timeIntervalSince(lastPopoverShown) > 0.8 else { return }
        cpuController?.closePopover()
        memoryController?.closePopover()
        diskController?.closePopover()
        networkController?.closePopover()
        tempController?.closePopover()
        weatherController?.closePopover()
    }
    
    private func refreshControllers() {
        syncItemVisibility()
        cpuController?.syncLength()
        memoryController?.syncLength()
        diskController?.syncLength()
        networkController?.syncLength()
        tempController?.syncLength()
        weatherController?.syncLength()
    }
    
    private func syncItemVisibility() {
        let prefs = AppPreferences.shared
        for metric in prefs.metricOrder {
            if let ctrl = controller(for: metric), let slot = ctrl.statusItem {
                slot.isVisible = prefs.isMetricVisible(metric)
            }
        }
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        closeAllPopovers()
        poller?.stop()
        CaffeinateManager.shared.stop()
        ClipboardPicker.shared.stop()
        caffeinateController?.removeFromStatusBar()
        clipboardController?.removeFromStatusBar()
        for slot in statusItemSlots {
            NSStatusBar.system.removeStatusItem(slot)
        }
        statusItemSlots.removeAll()
    }
}

