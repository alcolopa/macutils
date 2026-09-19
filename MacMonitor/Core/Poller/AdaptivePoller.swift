import Foundation
import AppKit

public final class AdaptivePoller: @unchecked Sendable {
    public enum State: Sendable {
        case passive     // Popovers closed; screen active
        case active      // At least one Popover displayed: 500ms interval, 25ms leeway
        case suspended   // Screen sleep or locked: Paused
    }
    
    private let cpuReader: MachCPUReader
    private let memoryReader: MachMemoryReader
    private let networkReader: MachNetworkReader
    private let diskReader: MachDiskReader
    private let batteryReader: MachBatteryReader
    private let tempReader = MachTemperatureReader()
    private let displayReader = MachDisplayReader()
    private let processReader = DarwinProcessReader()
    
    private let queue = DispatchQueue(label: "com.macmonitor.poller", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    
    private var currentState: State = .passive
    private var previousActiveState: State = .passive
    private var openPopoverCount: Int = 0
    private var tickCount: Int = 0
    private let lock = NSLock()
    
    private let weatherService = OpenWeatherMapService.shared
    private var weatherTimer: DispatchSourceTimer?
    private var lastWeatherStats: WeatherStats = .unconfigured
    
    public var onMetricsUpdated: (@Sendable @MainActor (CPUStats, MemoryStats, NetworkStats, DiskStats, BatteryStats, State) -> Void)?
    public var onExtendedMetricsUpdated: (@Sendable @MainActor (TemperatureStats, DisplayStats) -> Void)?
    public var onWeatherUpdated: (@Sendable @MainActor (WeatherStats) -> Void)?
    
    public init(
        cpuReader: MachCPUReader = MachCPUReader(),
        memoryReader: MachMemoryReader = MachMemoryReader(),
        networkReader: MachNetworkReader = MachNetworkReader(),
        diskReader: MachDiskReader = MachDiskReader(),
        batteryReader: MachBatteryReader = MachBatteryReader()
    ) {
        self.cpuReader = cpuReader
        self.memoryReader = memoryReader
        self.networkReader = networkReader
        self.diskReader = diskReader
        self.batteryReader = batteryReader
        setupWorkspaceObservers()
    }
    
    deinit {
        stop()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
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
    }
    
    public func registerPopoverState(isShown: Bool) {
        lock.lock()
        defer { lock.unlock() }
        
        if isShown {
            openPopoverCount += 1
        } else {
            openPopoverCount = max(0, openPopoverCount - 1)
        }
        
        let targetState: State = openPopoverCount > 0 ? .active : .passive
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
    }
    
    public func resume() {
        lock.lock()
        defer { lock.unlock() }
        guard currentState == .suspended else { return }
        currentState = previousActiveState
        reconfigureTimer(for: currentState)
    }
    
    public func reconfigure() {
        lock.lock()
        defer { lock.unlock() }
        reconfigureTimer(for: currentState)
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
            intervalMs = max(250, Int(userSec * 1000.0))
            leewayMs = 10
        case .active:
            intervalMs = 500
            leewayMs = 10
        case .suspended:
            return
        }
        
        let newTimer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
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
        let isPopoverOpen = openPopoverCount > 0
        let currentTick = tickCount
        lock.unlock()
        
        var topMem: [ProcessItem] = []
        var topCPU: [ProcessItem] = []
        var topNet: [NetworkProcessItem] = []
        if isPopoverOpen || (currentTick % 3 == 0) {
            let (memList, cpuList) = processReader.readTopProcesses(limit: 5)
            topMem = memList
            topCPU = cpuList
            topNet = networkReader.readTopNetworkProcesses(limit: 5)
        }
        
        let cpuStats = cpuReader.readSystemUsage(topProcesses: topCPU)
        let memStats = memoryReader.readMemoryUsage(topProcesses: topMem)
        let netStats = networkReader.readNetworkUsage(topProcesses: topNet)
        let diskStats = diskReader.readDiskUsage()
        let batStats = batteryReader.readBatteryUsage()
        let tempStats = tempReader.readTemperatures()
        let dispStats = displayReader.readDisplays()
        
        let state: State
        let callback: (@Sendable @MainActor (CPUStats, MemoryStats, NetworkStats, DiskStats, BatteryStats, State) -> Void)?
        let extCallback: (@Sendable @MainActor (TemperatureStats, DisplayStats) -> Void)?
        lock.lock()
        state = currentState
        callback = self.onMetricsUpdated
        extCallback = self.onExtendedMetricsUpdated
        lock.unlock()
        
        DispatchQueue.main.async {
            callback?(cpuStats, memStats, netStats, diskStats, batStats, state)
            extCallback?(tempStats, dispStats)
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDisplayChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }
    
    @objc private func handleScreenSleep() {
        suspend()
    }
    
    @objc private func handleScreenWake() {
        resume()
    }
    
    @objc private func handleDisplayChange() {
        // Trigger immediate tick when displays change
        queue.async { [weak self] in
            self?.tick()
        }
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
        }
    }
}
