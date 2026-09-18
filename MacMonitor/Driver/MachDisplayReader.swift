import Foundation
import AppKit
import CoreGraphics

public final class MachDisplayReader: @unchecked Sendable {
    private let lock = NSLock()
    
    public init() {}
    
    public func readDisplays() -> DisplayStats {
        lock.lock()
        defer { lock.unlock() }
        
        var displayInfos: [DisplayInfo] = []
        let screens = NSScreen.screens
        
        var activeDisplays = [CGDirectDisplayID](repeating: 0, count: 16)
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(16, &activeDisplays, &displayCount)
        
        for (index, screen) in screens.enumerated() {
            var displayID: CGDirectDisplayID = 0
            if let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                displayID = CGDirectDisplayID(num.uint32Value)
            } else if index < Int(displayCount) {
                displayID = activeDisplays[index]
            }
            
            let isMain = screen == NSScreen.main
            let isBuiltIn = CGDisplayIsBuiltin(displayID) != 0
            let bounds = screen.frame
            
            // Resolution (Pixels)
            let backingScale = screen.backingScaleFactor
            let pixelWidth = bounds.width * backingScale
            let pixelHeight = bounds.height * backingScale
            let resolution = CGSize(width: pixelWidth, height: pixelHeight)
            
            // Refresh Rate
            var refreshRate: Double = 60.0
            if let mode = CGDisplayCopyDisplayMode(displayID) {
                refreshRate = mode.refreshRate
                if refreshRate == 0 {
                    // ProMotion displays might return 0, query mode or fallback to 120 on Apple Silicon XDR
                    if isBuiltIn && (pixelWidth >= 3024 || pixelWidth >= 3456) {
                        refreshRate = 120.0
                    } else {
                        refreshRate = 60.0
                    }
                }
            }
            
            // Name
            let name = screen.localizedName.isEmpty ? (isBuiltIn ? "Built-in Liquid Retina XDR" : "External Display \(index + 1)") : screen.localizedName
            let colorSpaceName = screen.colorSpace?.localizedName ?? "Color LCD"
            
            let info = DisplayInfo(
                id: displayID,
                name: name,
                isMain: isMain,
                isBuiltIn: isBuiltIn,
                bounds: bounds,
                resolution: resolution,
                refreshRate: refreshRate,
                backingScaleFactor: backingScale,
                colorSpaceName: colorSpaceName
            )
            displayInfos.append(info)
        }
        
        return DisplayStats(displays: displayInfos, timestamp: mach_absolute_time())
    }
}
