import Foundation

public struct BatteryStats: Sendable {
    public let currentCapacity: Int        // 0 to 100
    public let isCharging: Bool
    public let isPluggedIn: Bool
    public let powerSourceState: String    // "AC Power" or "Battery Power"
    public let timeToEmptyMinutes: Int     // -1 if unknown / plugged in
    public let timeToFullMinutes: Int      // -1 if unknown / not charging
    public let healthPercentage: Int       // e.g. 96%
    public let cycleCount: Int
    public let timestamp: UInt64
    
    public init(
        currentCapacity: Int,
        isCharging: Bool,
        isPluggedIn: Bool,
        powerSourceState: String,
        timeToEmptyMinutes: Int = -1,
        timeToFullMinutes: Int = -1,
        healthPercentage: Int = 100,
        cycleCount: Int = 0,
        timestamp: UInt64
    ) {
        self.currentCapacity = currentCapacity
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.powerSourceState = powerSourceState
        self.timeToEmptyMinutes = timeToEmptyMinutes
        self.timeToFullMinutes = timeToFullMinutes
        self.healthPercentage = healthPercentage
        self.cycleCount = cycleCount
        self.timestamp = timestamp
    }
    
    public var formattedTimeRemaining: String {
        if isCharging {
            if timeToFullMinutes > 0 {
                let h = timeToFullMinutes / 60
                let m = timeToFullMinutes % 60
                return "\(h):\(String(format: "%02d", m)) until full"
            } else {
                return "Calculating..."
            }
        } else if isPluggedIn {
            return "Fully charged"
        } else {
            if timeToEmptyMinutes > 0 {
                let h = timeToEmptyMinutes / 60
                let m = timeToEmptyMinutes % 60
                return "\(h):\(String(format: "%02d", m)) remaining"
            } else {
                return "Calculating..."
            }
        }
    }
}
