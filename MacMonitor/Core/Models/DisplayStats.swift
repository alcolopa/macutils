import Foundation
import CoreGraphics

public struct DisplayInfo: Sendable, Identifiable {
    public var id: CGDirectDisplayID
    public let name: String
    public let isMain: Bool
    public let isBuiltIn: Bool
    public let bounds: CGRect
    public let resolution: CGSize          // Physical pixel or logical resolution
    public let refreshRate: Double         // e.g. 60.0 or 120.0 Hz
    public let backingScaleFactor: CGFloat // 1.0 or 2.0 (Retina)
    public let colorSpaceName: String
    
    public init(
        id: CGDirectDisplayID,
        name: String,
        isMain: Bool,
        isBuiltIn: Bool,
        bounds: CGRect,
        resolution: CGSize,
        refreshRate: Double,
        backingScaleFactor: CGFloat,
        colorSpaceName: String
    ) {
        self.id = id
        self.name = name
        self.isMain = isMain
        self.isBuiltIn = isBuiltIn
        self.bounds = bounds
        self.resolution = resolution
        self.refreshRate = refreshRate
        self.backingScaleFactor = backingScaleFactor
        self.colorSpaceName = colorSpaceName
    }
    
    public var formattedResolution: String {
        return "\(Int(resolution.width)) × \(Int(resolution.height))"
    }
    
    public var formattedRefreshRate: String {
        if refreshRate > 0 {
            return String(format: "%.0f Hz", refreshRate)
        }
        return "60 Hz"
    }
}

public struct DisplayStats: Sendable {
    public let displays: [DisplayInfo]
    public let activeDisplayCount: Int
    public let timestamp: UInt64
    
    public init(
        displays: [DisplayInfo] = [],
        timestamp: UInt64 = mach_absolute_time()
    ) {
        self.displays = displays
        self.activeDisplayCount = displays.count
        self.timestamp = timestamp
    }
}
