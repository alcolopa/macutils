import AppKit

public struct ProcessItem: Sendable, Identifiable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let name: String
    public let residentBytes: UInt64
    public let cpuPercentage: Double
    public let userTimeNanos: UInt64
    public let iconPath: String?
    
    public init(pid: Int32, name: String, residentBytes: UInt64, cpuPercentage: Double = 0.0, userTimeNanos: UInt64 = 0, iconPath: String? = nil) {
        self.iconPath = iconPath
        self.pid = pid
        self.name = name
        self.residentBytes = residentBytes
        self.cpuPercentage = cpuPercentage
        self.userTimeNanos = userTimeNanos
    }
    
    public var formattedMemory: String {
        let mb = Double(residentBytes) / (1024.0 * 1024.0)
        if mb >= 1024.0 {
            return String(format: "%.2f GB", mb / 1024.0)
        } else {
            return String(format: "%.0f MB", mb)
        }
    }
    
    public var formattedCPU: String {
        return String(format: "%.1f%%", min(max(cpuPercentage, 0.0), 100.0 * Double(ProcessInfo.processInfo.activeProcessorCount)))
    }
}

public struct NetworkProcessItem: Sendable, Identifiable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let name: String
    public let bytesInPerSec: Double
    public let bytesOutPerSec: Double
    public let totalBytesIn: UInt64
    public let totalBytesOut: UInt64
    public let iconPath: String?
    
    public init(
        pid: Int32,
        name: String,
        bytesInPerSec: Double = 0.0,
        bytesOutPerSec: Double = 0.0,
        totalBytesIn: UInt64 = 0,
        totalBytesOut: UInt64 = 0,
        iconPath: String? = nil
    ) {
        self.iconPath = iconPath
        self.pid = pid
        self.name = name
        self.bytesInPerSec = bytesInPerSec
        self.bytesOutPerSec = bytesOutPerSec
        self.totalBytesIn = totalBytesIn
        self.totalBytesOut = totalBytesOut
    }
    
    public var formattedSpeed: String {
        let totalSpeed = bytesInPerSec + bytesOutPerSec
        if totalSpeed > 0.05 {
            let inStr = NetworkStats.formatSpeed(bytesInPerSec)
            let outStr = NetworkStats.formatSpeed(bytesOutPerSec)
            return "⇣\(inStr) ⇡\(outStr)"
        } else {
            return NetworkStats.formatTotalBytes(totalBytesIn + totalBytesOut)
        }
    }
    
    public var formattedTotal: String {
        return NetworkStats.formatTotalBytes(totalBytesIn + totalBytesOut)
    }
}

