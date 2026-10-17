import Foundation
import AppKit
import Network
import CoreGraphics

public final class AdaptivePoller: @unchecked Sendable {
    public enum State: Sendable {
        case passive     // Popovers closed; screen active
        case active      // At least one Popover displayed: 500ms interval
        case suspended   // Screen sleep, system sleep, or locked: Paused
    }
    
    private let cpuReader: MachCPUReader
    private let memoryReader: MachMemoryReader
    private let networkReader: MachNetworkReader
    private let diskReader: MachDiskReader
    private let tempReader = MachTemperatureReader()
    private let processReader = DarwinProcessReader()
    
    private let queue = DispatchQueue(label: "com.macutils.poller", qos: .utility)
    private var timer: DispatchSourceTimer?
    
    private var currentState: State = .passive
    private var previousActiveState: State = .passive
    private var openPopovers: Set<MetricType> = []
    private var legacyOpenPopoverCount: Int = 0
    private var tickCount: Int = 0
    private var isIdleThrottled: Bool = false
    private let lock = NSLock()
    
    private let weatherService = OpenWeatherMapService.shared
    private var weatherTimer: DispatchSourceTimer?
    private var pathMonitor: NWPathMonitor?
    private var weatherRetryTask: Task<Void, Never>?
    private var _lastWeatherStats: WeatherStats = .unconfigured
    // Read from the path-monitor queue and written on the main actor, so guard it.
    private var lastWeatherStats: WeatherStats {
        get { lock.lock(); defer { lock.unlock() }; return _lastWeatherStats }
        set { lock.lock(); defer { lock.unlock() }; _lastWeatherStats = newValue }
    }
    
    public var onMetricsUpdated: (@Sendable @MainActor (CPUStats, MemoryStats, NetworkStats, DiskStats, State) -> Void)?
    public var onExtendedMetricsUpdated: (@Sendable @MainActor (TemperatureStats) -> Void)?
    public var onWeatherUpdated: (@Sendable @MainActor (WeatherStats) -> Void)?
    
    public init(
        cpuReader: MachCPUReader = MachCPUReader(),
        memoryReader: MachMemoryReader = MachMemoryReader(),
        networkReader: MachNetworkReader = MachNetworkReader(),
        diskReader: MachDiskReader = MachDiskReader()
    ) {
        self.cpuReader = cpuReader
        self.memoryReader = memoryReader
        self.networkReader = networkReader
        self.diskReader = diskReader
        setupWorkspaceObservers()
    }
    
    deinit {
        stop()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }
    
    public func start() {
        lock.lock()
        defer { lock.unlock() }
        reconfigureTimer(for: currentState)
        startWeatherTimer()
    }
    
    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        timer?.setEventHandler(handler: nil)
        timer?.cancel()
        timer = nil
        weatherTimer?.cancel()
        weatherTimer = nil
        pathMonitor?.cancel()
        pathMonitor = nil
        weatherRetryTask?.cancel()
        weatherRetryTask = nil
    }
    
    public func registerPopoverState(for metric: MetricType, isShown: Bool) {
        lock.lock()
        defer { lock.unlock() }
        
        if isShown {
            openPopovers.insert(metric)
        } else {
            openPopovers.remove(metric)
        }
        
        updateTargetStateLocked()
    }
    
    public func registerPopoverState(isShown: Bool) {
        lock.lock()
        defer { lock.unlock() }
        
        if isShown {
            legacyOpenPopoverCount += 1
        } else {
            legacyOpenPopoverCount = max(0, legacyOpenPopoverCount - 1)
        }
        
        updateTargetStateLocked()
    }
    
    private func updateTargetStateLocked() {
        let hasOpenPopover = !openPopovers.isEmpty || legacyOpenPopoverCount > 0
        let targetState: State = hasOpenPopover ? .active : .passive
        
        guard currentState != .suspended else {
            previousActiveState = targetState
            return
        }
        
        if currentState != targetState {
            currentState = targetState
            reconfigureTimer(for: targetState)
        }
    }
    
    public func suspend() {
        lock.lock()
        defer { lock.unlock() }
        guard currentState != .suspended else { return }
        previousActiveState = currentState
        currentState = .suspended
        timer?.cancel()
        timer = nil
        weatherTimer?.cancel()
        weatherTimer = nil
    }
    
    public func resume() {
        lock.lock()
        defer { lock.unlock() }
        guard currentState == .suspended else { return }
        currentState = previousActiveState
        reconfigureTimer(for: currentState)
        startWeatherTimer()
    }
    
    public func reconfigure() {
        lock.lock()
        defer { lock.unlock() }
        reconfigureTimer(for: currentState)
    }
    
    private func isSystemIdle() -> Bool {
        // CGEventSource measures seconds since any user input (keyboard, mouse, trackpad)
        let idleSec = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        return idleSec >= 45.0
    }
    
    private func reconfigureTimer(for state: State) {
        timer?.cancel()
        timer = nil
        
        guard state != .suspended else { return }
        
        let intervalMs: Int
        let leewayMs: Int
        
        switch state {
        case .passive:
            let userSec = AppPreferences.shared.passiveInterval
            if isIdleThrottled {
                // When computer is unattended, throttle to 5-10s with generous leeway to let CPU sleep
                intervalMs = max(5000, Int(userSec * 2500.0))
                leewayMs = 1000
            } else {
                intervalMs = max(500, Int(userSec * 1000.0))
                leewayMs = max(100, intervalMs / 4)
            }
        case .active:
            intervalMs = 500
            leewayMs = 50
        case .suspended:
            return
        }
        
        // Coalesced timer without .strict allows macOS power management to keep CPU package in deep C-states
        let newTimer = DispatchSource.makeTimerSource(queue: queue)
        newTimer.schedule(
            deadline: .now(),
            repeating: .milliseconds(intervalMs),
            leeway: .milliseconds(leewayMs)
        )
        
        newTimer.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.tick()
        }
        
        newTimer.resume()
        self.timer = newTimer
    }
    
    private func tick() {
        lock.lock()
        tickCount += 1
        let popovers = openPopovers
        let isAnyPopoverOpen = !popovers.isEmpty || legacyOpenPopoverCount > 0
        let currentIdle = !isAnyPopoverOpen && isSystemIdle()
        
        if currentIdle != isIdleThrottled {
            isIdleThrottled = currentIdle
            reconfigureTimer(for: currentState)
        }
        lock.unlock()
        
        // Only run expensive top process reading or nettop child processes when a relevant popover is actively open!
        var topMem: [ProcessItem] = []
        var topCPU: [ProcessItem] = []
        var topNet: [NetworkProcessItem] = []
        
        if isAnyPopoverOpen {
            let needsProc = popovers.isEmpty || popovers.contains(.cpu) || popovers.contains(.memory)
            let needsNet = popovers.isEmpty || popovers.contains(.network)
            
            if needsProc {
                let (memList, cpuList) = processReader.readTopProcesses(limit: 5)
                topMem = memList
                topCPU = cpuList
            }
            if needsNet {
                topNet = networkReader.readTopNetworkProcesses(limit: 5)
            }
        }
        
        let cpuStats = cpuReader.readSystemUsage(topProcesses: topCPU)
        let memStats = memoryReader.readMemoryUsage(topProcesses: topMem)
        let netStats = networkReader.readNetworkUsage(topProcesses: topNet)
        let diskStats = diskReader.readDiskUsage()
        let tempStats = tempReader.readTemperatures()
        
        let state: State
        let callback: (@Sendable @MainActor (CPUStats, MemoryStats, NetworkStats, DiskStats, State) -> Void)?
        let extCallback: (@Sendable @MainActor (TemperatureStats) -> Void)?
        lock.lock()
        state = currentState
        callback = self.onMetricsUpdated
        extCallback = self.onExtendedMetricsUpdated
        lock.unlock()
        
        DispatchQueue.main.async {
            callback?(cpuStats, memStats, netStats, diskStats, state)
            extCallback?(tempStats)
        }
    }
    
    private func setupWorkspaceObservers() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        wsCenter.addObserver(
            self,
            selector: #selector(handleScreenSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        wsCenter.addObserver(
            self,
            selector: #selector(handleScreenWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        wsCenter.addObserver(
            self,
            selector: #selector(handleSystemSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        wsCenter.addObserver(
            self,
            selector: #selector(handleSystemWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        
        let distCenter = DistributedNotificationCenter.default()
        distCenter.addObserver(
            self,
            selector: #selector(handleScreenLocked),
            name: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil
        )
        distCenter.addObserver(
            self,
            selector: #selector(handleScreenUnlocked),
            name: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )
    }
    
    @objc private func handleScreenSleep() {
        suspend()
    }
    
    @objc private func handleScreenWake() {
        resume()
    }
    
    @objc private func handleSystemSleep() {
        suspend()
    }
    
    @objc private func handleSystemWake() {
        resume()
    }
    
    @objc private func handleScreenLocked() {
        suspend()
    }
    
    @objc private func handleScreenUnlocked() {
        resume()
    }
    
    // MARK: - Weather Polling
    
    public func refreshWeather() {
        Task { [weak self] in
            await self?.fetchWeatherAsync()
        }
    }
    
    private func startWeatherTimer() {
        weatherTimer?.cancel()
        weatherTimer = nil
        
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let intervalSec = Int(AppPreferences.shared.weatherUpdateInterval)
        timer.schedule(
            deadline: .now() + .milliseconds(500),
            repeating: .seconds(intervalSec),
            leeway: .seconds(10)
        )
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            Task {
                await self.fetchWeatherAsync()
            }
        }
        timer.resume()
        self.weatherTimer = timer
        startPathMonitor()
    }
    
    private func startPathMonitor() {
        guard pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self, path.status == .satisfied else { return }
            let stats = self.lastWeatherStats
            if stats.isConfigured && (stats.current == nil || stats.errorMessage != nil) {
                Task { await self.fetchWeatherAsync() }
            }
        }
        monitor.start(queue: queue)
        pathMonitor = monitor
    }
    
    private func fetchWeatherAsync() async {
        let prefs = AppPreferences.shared
        let apiKey = prefs.weatherApiKey
        let city = prefs.weatherCity
        
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let stats = WeatherStats.unconfigured
            await MainActor.run { [weak self] in
                self?.lastWeatherStats = stats
                self?.onWeatherUpdated?(stats)
            }
            return
        }
        
        do {
            let stats = try await weatherService.fetchWeather(apiKey: apiKey, location: city)
            await MainActor.run { [weak self] in
                self?.lastWeatherStats = stats
                self?.onWeatherUpdated?(stats)
            }
        } catch {
            let errStats = WeatherStats(
                current: self.lastWeatherStats.current,
                forecast: self.lastWeatherStats.forecast,
                lastUpdated: self.lastWeatherStats.lastUpdated,
                errorMessage: error.localizedDescription,
                isConfigured: true
            )
            await MainActor.run { [weak self] in
                self?.lastWeatherStats = errStats
                self?.onWeatherUpdated?(errStats)
            }
            // Retry soon rather than waiting a full update interval.
            weatherRetryTask?.cancel()
            weatherRetryTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.fetchWeatherAsync()
            }
        }
    }
}
