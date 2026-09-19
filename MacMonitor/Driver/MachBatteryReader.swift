import Foundation
import Darwin
import IOKit.ps

public final class MachBatteryReader: @unchecked Sendable {
    public init() {}
    
    public func readBatteryUsage() -> BatteryStats {
        let now = mach_absolute_time()
        
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return BatteryStats(currentCapacity: 100, isCharging: false, isPluggedIn: true, powerSourceState: "AC Power", timestamp: now)
        }
        
        let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        guard let first = sources?.first,
              let desc = IOPSGetPowerSourceDescription(blob, first)?.takeUnretainedValue() as? [String: Any] else {
            return BatteryStats(currentCapacity: 100, isCharging: false, isPluggedIn: true, powerSourceState: "AC Power", timestamp: now)
        }
        
        let cap = desc[kIOPSCurrentCapacityKey as String] as? Int ?? 100
        let state = desc[kIOPSPowerSourceStateKey as String] as? String ?? "AC Power"
        let isPluggedIn = (state == kIOPSACPowerValue as String)
        let isCharging = desc[kIOPSIsChargingKey as String] as? Bool ?? false
        let timeToEmpty = desc[kIOPSTimeToEmptyKey as String] as? Int ?? -1
        let timeToFull = desc[kIOPSTimeToFullChargeKey as String] as? Int ?? -1
        
        let health = readHealth()
        
        return BatteryStats(
            currentCapacity: cap,
            isCharging: isCharging,
            isPluggedIn: isPluggedIn,
            powerSourceState: state,
            timeToEmptyMinutes: timeToEmpty,
            timeToFullMinutes: timeToFull,
            healthPercentage: health.percentage,
            cycleCount: health.cycles,
            timestamp: now
        )
    }
    
    /// Real battery health (max vs. design capacity) and cycle count from the AppleSmartBattery registry entry.
    private func readHealth() -> (percentage: Int, cycles: Int) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return (100, 0) }
        defer { IOObjectRelease(service) }
        
        func int(_ key: String) -> Int? {
            (IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.intValue
        }
        
        let batteryData = IORegistryEntryCreateCFProperty(service, "BatteryData" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any] ?? [:]
        func value(_ key: String) -> Int? {
            int(key) ?? (batteryData[key] as? NSNumber)?.intValue
        }
        
        let cycles = value("CycleCount") ?? 0
        let design = value("DesignCapacity") ?? 0
        // Same basis as System Settings: nominal (max) charge capacity relative to design capacity.
        let maxCap = value("NominalChargeCapacity") ?? value("AppleRawMaxCapacity") ?? value("FullChargeCapacity") ?? 0
        guard design > 0, maxCap > 0 else { return (100, cycles) }
        return (min(100, Int((Double(maxCap) / Double(design) * 100).rounded())), cycles)
    }
}
