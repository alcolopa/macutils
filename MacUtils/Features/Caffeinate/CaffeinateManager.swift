import Foundation
import IOKit.pwr_mgt

/// Keeps the Mac awake by holding IOKit power assertions (the same mechanism as `caffeinate(8)`).
@MainActor
public final class CaffeinateManager {
    public static let shared = CaffeinateManager()
    
    public private(set) var isActive = false
    /// When a timed session ends; nil while off or running indefinitely.
    public private(set) var endDate: Date?
    public static let didChange = Notification.Name("MacUtilsCaffeinateDidChange")
    
    /// Duration choices shown in menus and settings; nil means until turned off.
    public static let presets: [(title: String, seconds: TimeInterval?)] = [
        ("15 minutes", 15 * 60), ("30 minutes", 30 * 60), ("1 hour", 3600),
        ("2 hours", 2 * 3600), ("4 hours", 4 * 3600), ("8 hours", 8 * 3600),
        ("Until I turn it off", nil)
    ]
    
    private var systemAssertion = IOPMAssertionID(0)
    private var displayAssertion = IOPMAssertionID(0)
    private var timer: Timer?
    
    private init() {}
    
    /// Starts a session using the duration chosen in settings.
    public func startDefault() {
        let d = AppPreferences.shared.caffeinateDefaultDuration
        start(duration: d > 0 ? d : nil, keepDisplayAwake: AppPreferences.shared.caffeinateKeepDisplayAwake)
    }
    
    /// Starts (or restarts) a session. `duration == nil` keeps the Mac awake until stopped.
    public func start(duration: TimeInterval?, keepDisplayAwake: Bool) {
        stop(notify: false)
        let reason = "MacUtils Caffeinate" as CFString
        let ok = IOPMAssertionCreateWithName(
            "PreventUserIdleSystemSleep" as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &systemAssertion) == kIOReturnSuccess
        guard ok else { systemAssertion = 0; return }
        if keepDisplayAwake {
            if IOPMAssertionCreateWithName(
                "PreventUserIdleDisplaySleep" as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &displayAssertion) != kIOReturnSuccess {
                displayAssertion = 0
            }
        }
        isActive = true
        if let duration {
            endDate = Date().addingTimeInterval(duration)
            timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop() }
            }
        }
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
    
    public func stop() { stop(notify: true) }
    
    private func stop(notify: Bool) {
        timer?.invalidate()
        timer = nil
        if systemAssertion != 0 { IOPMAssertionRelease(systemAssertion); systemAssertion = 0 }
        if displayAssertion != 0 { IOPMAssertionRelease(displayAssertion); displayAssertion = 0 }
        let wasActive = isActive
        isActive = false
        endDate = nil
        if notify && wasActive { NotificationCenter.default.post(name: Self.didChange, object: nil) }
    }
}
