import Foundation

public struct BatteryStats: Sendable {
    public let hasBattery: Bool
    public let percentage: Double
    public let isCharging: Bool
    public let isPluggedIn: Bool
    public let timeRemainingMinutes: Int?
    public let healthPercentage: Double?
    public let cycleCount: Int?
    public let maxCapacityMAh: Int?
    public let designCapacityMAh: Int?
    public let wattage: Double?
    public let voltageMilliVolts: Int?
    public let amperageMilliAmps: Int?
    public let temperatureCelsius: Double?
    public let powerSourceState: String
    public let condition: String
    
    public init(
        hasBattery: Bool = true,
        percentage: Double = 100.0,
        isCharging: Bool = false,
        isPluggedIn: Bool = true,
        timeRemainingMinutes: Int? = nil,
        healthPercentage: Double? = nil,
        cycleCount: Int? = nil,
        maxCapacityMAh: Int? = nil,
        designCapacityMAh: Int? = nil,
        wattage: Double? = nil,
        voltageMilliVolts: Int? = nil,
        amperageMilliAmps: Int? = nil,
        temperatureCelsius: Double? = nil,
        powerSourceState: String = "AC Power",
        condition: String = "Normal"
    ) {
        self.hasBattery = hasBattery
        self.percentage = percentage
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.timeRemainingMinutes = timeRemainingMinutes
        self.healthPercentage = healthPercentage
        self.cycleCount = cycleCount
        self.maxCapacityMAh = maxCapacityMAh
        self.designCapacityMAh = designCapacityMAh
        self.wattage = wattage
        self.voltageMilliVolts = voltageMilliVolts
        self.amperageMilliAmps = amperageMilliAmps
        self.temperatureCelsius = temperatureCelsius
        self.powerSourceState = powerSourceState
        self.condition = condition
    }
    
    public var formattedPercentage: String {
        return String(format: "%.0f%%", percentage)
    }
    
    public var formattedTimeRemaining: String {
        guard let mins = timeRemainingMinutes, mins > 0 else {
            return isCharging ? "Calculating..." : (isPluggedIn ? "Fully Charged" : "Unknown")
        }
        let hours = mins / 60
        let remainder = mins % 60
        if hours > 0 {
            return "\(hours)h \(remainder)m"
        } else {
            return "\(remainder)m"
        }
    }
    
    public var formattedWattage: String {
        guard let w = wattage else { return "-- W" }
        return String(format: "%.1f W", abs(w))
    }
    
    public static let unavailable = BatteryStats(
        hasBattery: false,
        percentage: 100.0,
        isCharging: false,
        isPluggedIn: true,
        timeRemainingMinutes: nil,
        healthPercentage: nil,
        cycleCount: nil,
        powerSourceState: "AC Power (Desktop)",
        condition: "N/A"
    )
}
