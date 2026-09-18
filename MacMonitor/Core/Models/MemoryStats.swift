import Foundation

public enum MemoryPressureState: String, Sendable {
    case normal   = "Normal"
    case warning  = "Warning"
    case critical = "Critical"
}

public struct SwapStats: Sendable {
    public let totalBytes: UInt64
    public let usedBytes: UInt64
    public let freeBytes: UInt64
    
    public init(totalBytes: UInt64, usedBytes: UInt64, freeBytes: UInt64) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.freeBytes = freeBytes
    }
    
    public var usedPercentage: Double {
        guard totalBytes > 0 else { return 0.0 }
        return (Double(usedBytes) / Double(totalBytes)) * 100.0
    }
}

public struct MemoryStats: Sendable {
    public let totalBytes: UInt64
    public let freeBytes: UInt64
    public let activeBytes: UInt64
    public let inactiveBytes: UInt64
    public let wiredBytes: UInt64
    public let compressedBytes: UInt64
    public let purgeableBytes: UInt64
    public let swap: SwapStats
    public let pressureState: MemoryPressureState
    public let pressurePercentage: Double // 0 to 100%
    public let topProcesses: [ProcessItem]
    
    public init(
        totalBytes: UInt64,
        freeBytes: UInt64,
        activeBytes: UInt64,
        inactiveBytes: UInt64,
        wiredBytes: UInt64,
        compressedBytes: UInt64,
        purgeableBytes: UInt64 = 0,
        swap: SwapStats = SwapStats(totalBytes: 0, usedBytes: 0, freeBytes: 0),
        pressureState: MemoryPressureState = .normal,
        pressurePercentage: Double = 20.0,
        topProcesses: [ProcessItem] = []
    ) {
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
        self.activeBytes = activeBytes
        self.inactiveBytes = inactiveBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.purgeableBytes = purgeableBytes
        self.swap = swap
        self.pressureState = pressureState
        self.pressurePercentage = pressurePercentage
        self.topProcesses = topProcesses
    }
    
    public var appBytes: UInt64 {
        let raw = activeBytes + inactiveBytes
        return raw >= purgeableBytes ? raw - purgeableBytes : raw
    }
    
    public var usedBytes: UInt64 {
        return appBytes + wiredBytes + compressedBytes
    }
    
    public var usedPercentage: Double {
        guard totalBytes > 0 else { return 0.0 }
        return min(max((Double(usedBytes) / Double(totalBytes)) * 100.0, 0.0), 100.0)
    }
}
