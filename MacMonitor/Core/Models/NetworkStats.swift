import Foundation

public struct NetworkStats: Sendable {
    public let bytesInPerSec: Double     // Instantaneous download rate in bytes/sec
    public let bytesOutPerSec: Double    // Instantaneous upload rate in bytes/sec
    public let totalBytesIn: UInt64      // Cumulative bytes downloaded
    public let totalBytesOut: UInt64     // Cumulative bytes uploaded
    public let primaryInterface: String  // e.g. "en0"
    public let localIPAddress: String    // e.g. "192.168.0.103"
    public let peakBytesInPerSec: Double
    public let peakBytesOutPerSec: Double
    public let topProcesses: [NetworkProcessItem]
    public let timestamp: UInt64         // mach_absolute_time
    
    public init(
        bytesInPerSec: Double,
        bytesOutPerSec: Double,
        totalBytesIn: UInt64,
        totalBytesOut: UInt64,
        primaryInterface: String,
        localIPAddress: String = "127.0.0.1",
        peakBytesInPerSec: Double = 0.0,
        peakBytesOutPerSec: Double = 0.0,
        topProcesses: [NetworkProcessItem] = [],
        timestamp: UInt64
    ) {
        self.bytesInPerSec = bytesInPerSec
        self.bytesOutPerSec = bytesOutPerSec
        self.totalBytesIn = totalBytesIn
        self.totalBytesOut = totalBytesOut
        self.primaryInterface = primaryInterface
        self.localIPAddress = localIPAddress
        self.peakBytesInPerSec = peakBytesInPerSec
        self.peakBytesOutPerSec = peakBytesOutPerSec
        self.topProcesses = topProcesses
        self.timestamp = timestamp
    }
    
    public static func formatSpeed(_ bytesPerSec: Double) -> String {
        let kb: Double = 1024
        let mb: Double = 1024 * 1024
        let gb: Double = 1024 * 1024 * 1024
        
        if bytesPerSec >= gb {
            return String(format: "%.2f GB/s", bytesPerSec / gb)
        } else if bytesPerSec >= mb {
            return String(format: "%.1f MB/s", bytesPerSec / mb)
        } else if bytesPerSec >= kb {
            return String(format: "%.0f KB/s", bytesPerSec / kb)
        } else {
            return String(format: "%.0f B/s", bytesPerSec)
        }
    }
    
    public static func formatTotalBytes(_ bytes: UInt64) -> String {
        let kb: Double = 1024
        let mb: Double = 1024 * 1024
        let gb: Double = 1024 * 1024 * 1024
        let tb: Double = 1024 * 1024 * 1024 * 1024
        let b = Double(bytes)
        
        if b >= tb {
            return String(format: "%.2f TB", b / tb)
        } else if b >= gb {
            return String(format: "%.2f GB", b / gb)
        } else if b >= mb {
            return String(format: "%.1f MB", b / mb)
        } else if b >= kb {
            return String(format: "%.0f KB", b / kb)
        } else {
            return "\(bytes) B"
        }
    }
}
