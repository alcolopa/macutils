import Foundation

public struct VolumeInfo: Sendable {
    public let name: String
    public let mountPoint: String
    public let totalBytes: UInt64
    public let usedBytes: UInt64
    public let freeBytes: UInt64
    
    public init(name: String, mountPoint: String, totalBytes: UInt64, usedBytes: UInt64, freeBytes: UInt64) {
        self.name = name
        self.mountPoint = mountPoint
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.freeBytes = freeBytes
    }
    
    public var usedPercentage: Double {
        guard totalBytes > 0 else { return 0.0 }
        return min(max((Double(usedBytes) / Double(totalBytes)) * 100.0, 0.0), 100.0)
    }
}

public struct DiskStats: Sendable {
    public let rootVolume: VolumeInfo
    public let allVolumes: [VolumeInfo]
    public let timestamp: UInt64
    
    public init(rootVolume: VolumeInfo, allVolumes: [VolumeInfo], timestamp: UInt64) {
        self.rootVolume = rootVolume
        self.allVolumes = allVolumes
        self.timestamp = timestamp
    }
    
    public static func formatBytes(_ bytes: UInt64) -> String {
        let gb = 1024.0 * 1024.0 * 1024.0
        let tb = gb * 1024.0
        let b = Double(bytes)
        if b >= tb {
            return String(format: "%.1f TB", b / tb)
        } else {
            return String(format: "%.0f GB", b / gb)
        }
    }
}
