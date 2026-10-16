import Foundation
import IOKit.pwr_mgt

/// Keeps the Mac awake by holding IOKit power assertions (the same mechanism as `caffeinate(8)`).
@MainActor
public final class CaffeinateManager {
    public static let shared = CaffeinateManager()
    
    public private(set) var isActive = false
    /// When a timed session ends; nil while off or running indefinitely.
    public private(set) var endDate: Date?
    public var onChange: (() -> Void)?
    
    private var systemAssertion = IOPMAssertionID(0)
    private var displayAssertion = IOPMAssertionID(0)
    private var timer: Timer?
    
    private init() {}
    
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
        onChange?()
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
        if notify && wasActive { onChange?() }
    }
}
