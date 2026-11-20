import Foundation
import IOKit
import IOKit.ps

public final class MachBatteryReader: @unchecked Sendable {
    private let lock = NSLock()
    
    public init() {}
    
    public func readBatteryUsage() -> BatteryStats {
        lock.lock()
        defer { lock.unlock() }
        
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              !sources.isEmpty else {
            return .unavailable
        }
        
        var foundBattery = false
        var pct: Double = 100.0
        var isCharging = false
        var isPluggedIn = true
        var timeRemaining: Int? = nil
        var stateStr = "AC Power"
        
        for ps in sources {
            if let desc = IOPSGetPowerSourceDescription(snapshot, ps)?.takeUnretainedValue() as? [String: Any] {
                let type = desc[kIOPSTypeKey as String] as? String ?? ""
                if type == (kIOPSInternalBatteryType as String) {
                    foundBattery = true
                    if let cur = desc[kIOPSCurrentCapacityKey as String] as? Double,
                       let maxCap = desc[kIOPSMaxCapacityKey as String] as? Double, maxCap > 0 {
                        pct = min(Swift.max((cur / maxCap) * 100.0, 0.0), 100.0)
                    } else if let curInt = desc[kIOPSCurrentCapacityKey as String] as? Int {
                        pct = Double(curInt)
                    }
                    
                    isCharging = desc[kIOPSIsChargingKey as String] as? Bool ?? false
                    if let powerState = desc[kIOPSPowerSourceStateKey as String] as? String {
                        stateStr = powerState
                        isPluggedIn = powerState == (kIOPSACPowerValue as String)
                    }
                    
                    if let timeToEmpty = desc[kIOPSTimeToEmptyKey as String] as? Int, timeToEmpty > 0 {
                        timeRemaining = timeToEmpty
                    } else if let timeToFull = desc[kIOPSTimeToFullChargeKey as String] as? Int, timeToFull > 0 {
                        timeRemaining = timeToFull
                    }
                    break
                }
            }
        }
        
        guard foundBattery else {
            return .unavailable
        }
        
        // Query AppleSmartBattery for deep hardware details (cycle count, voltage, amperage, health)
        var cycleCount: Int? = nil
        var maxCap: Int? = nil
        var designCap: Int? = nil
        var healthPct: Double? = nil
        var voltageMV: Int? = nil
        var amperageMA: Int? = nil
        var wattage: Double? = nil
        var tempC: Double? = nil
        var condition = "Normal"
        
        var iterator: io_iterator_t = 0
        let match = IOServiceMatching("AppleSmartBattery")
        if IOServiceGetMatchingServices(kIOMainPortDefault, match, &iterator) == KERN_SUCCESS {
            var entry = IOIteratorNext(iterator)
            while entry != 0 {
                var props: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                   let dict = props?.takeRetainedValue() as? [String: Any] {
                    cycleCount = dict["CycleCount"] as? Int
                    voltageMV = dict["Voltage"] as? Int
                    amperageMA = dict["Amperage"] as? Int
                    
                    if let v = voltageMV, let a = amperageMA {
                        // V (mV) * A (mA) = uW -> / 1,000,000 = Watts
                        wattage = (Double(v) * Double(a)) / 1_000_000.0
                    }
                    
                    if let rawMax = dict["AppleRawMaxCapacity"] as? Int ?? dict["NominalChargeCapacity"] as? Int ?? dict["MaxCapacity"] as? Int {
                        maxCap = rawMax
                    }
                    if let rawDesign = dict["DesignCapacity"] as? Int {
                        designCap = rawDesign
                    }
                    
                    if let m = maxCap, let d = designCap, d > 0 {
                        healthPct = min(max((Double(m) / Double(d)) * 100.0, 0.0), 100.0)
                    }
                    
                    if let rawTemp = dict["Temperature"] as? Int {
                        tempC = Double(rawTemp) / 100.0
                    }
                    
                    if let cond = dict["PermanentFailureStatus"] as? Int, cond != 0 {
                        condition = "Service Recommended"
                    }
                }
                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }
            IOObjectRelease(iterator)
        }
        
        return BatteryStats(
            hasBattery: true,
            percentage: pct,
            isCharging: isCharging,
            isPluggedIn: isPluggedIn,
            timeRemainingMinutes: timeRemaining,
            healthPercentage: healthPct,
            cycleCount: cycleCount,
            maxCapacityMAh: maxCap,
            designCapacityMAh: designCap,
            wattage: wattage,
            voltageMilliVolts: voltageMV,
            amperageMilliAmps: amperageMA,
            temperatureCelsius: tempC,
            powerSourceState: stateStr,
            condition: condition
        )
    }
}
