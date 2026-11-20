import Foundation
import AppKit
import CoreGraphics
import IOKit

public struct DisplayItem: Sendable, Identifiable {
    public var id: CGDirectDisplayID { displayID }
    public let displayID: CGDirectDisplayID
    public let name: String
    public let isBuiltIn: Bool
    public let supportsBrightness: Bool
    public let supportsVolume: Bool
    public let brightness: Int   // 0...100
    public let volume: Int       // 0...100
}

/// Controls built-in display brightness (via DisplayServices) and external monitor
/// brightness & speaker volume (via Apple Silicon IOAVService DDC/CI).
public final class DisplayControlManager: @unchecked Sendable {
    public static let shared = DisplayControlManager()
    
    private let ddcQueue = DispatchQueue(label: "com.macutils.ddc", qos: .userInteractive)
    private let lock = NSLock()
    private var cachedBrightness: [CGDirectDisplayID: Int] = [:]
    private var cachedVolume: [CGDirectDisplayID: Int] = [:]
    
    // MARK: - Dynamically loaded C entry points
    
    private typealias DSGetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias DSSetBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    
    private typealias IOAVServiceCreateWithServiceFn = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    private typealias IOAVServiceWriteI2CFn = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutablePointer<UInt8>, UInt32) -> IOReturn
    private typealias IOAVServiceReadI2CFn = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutablePointer<UInt8>, UInt32) -> IOReturn
    
    private let dsGetBrightness: DSGetBrightnessFn?
    private let dsSetBrightness: DSSetBrightnessFn?
    private let avCreateWithService: IOAVServiceCreateWithServiceFn?
    private let avWriteI2C: IOAVServiceWriteI2CFn?
    private let avReadI2C: IOAVServiceReadI2CFn?
    
    public static let vcpBrightness: UInt8 = 0x10
    public static let vcpVolume: UInt8 = 0x62
    
    public init() {
        if let dsHandle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY) {
            dsGetBrightness = unsafeBitCast(dlsym(dsHandle, "DisplayServicesGetBrightness"), to: DSGetBrightnessFn?.self)
            dsSetBrightness = unsafeBitCast(dlsym(dsHandle, "DisplayServicesSetBrightness"), to: DSSetBrightnessFn?.self)
        } else {
            dsGetBrightness = nil
            dsSetBrightness = nil
        }
        
        if let ioHandle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY) {
            avCreateWithService = unsafeBitCast(dlsym(ioHandle, "IOAVServiceCreateWithService"), to: IOAVServiceCreateWithServiceFn?.self)
            avWriteI2C = unsafeBitCast(dlsym(ioHandle, "IOAVServiceWriteI2C"), to: IOAVServiceWriteI2CFn?.self)
            avReadI2C = unsafeBitCast(dlsym(ioHandle, "IOAVServiceReadI2C"), to: IOAVServiceReadI2CFn?.self)
        } else {
            avCreateWithService = nil
            avWriteI2C = nil
            avReadI2C = nil
        }
    }
    
    // MARK: - Display Enumeration
    
    @MainActor
    public func connectedDisplays() -> [DisplayItem] {
        let externalServices = discoverExternalAVServices()
        var externalIndex = 0
        var items: [DisplayItem] = []
        
        for screen in NSScreen.screens {
            guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            let displayID = CGDirectDisplayID(num.uint32Value)
            let isBuiltIn = CGDisplayIsBuiltin(displayID) != 0
            let name = screen.localizedName
            
            if isBuiltIn {
                let b = readBuiltInBrightness(displayID) ?? cachedBrightnessValue(for: displayID, default: 75)
                items.append(DisplayItem(
                    displayID: displayID,
                    name: name,
                    isBuiltIn: true,
                    supportsBrightness: dsSetBrightness != nil,
                    supportsVolume: false,
                    brightness: b,
                    volume: 0
                ))
            } else {
                let hasDDC = externalIndex < externalServices.count
                let b = cachedBrightnessValue(for: displayID, default: 75)
                let v = cachedVolumeValue(for: displayID, default: 50)
                items.append(DisplayItem(
                    displayID: displayID,
                    name: name,
                    isBuiltIn: false,
                    supportsBrightness: hasDDC,
                    supportsVolume: hasDDC,
                    brightness: b,
                    volume: v
                ))
                externalIndex += 1
            }
        }
        
        return items
    }
    
    // MARK: - Brightness & Volume Control
    
    public func setBrightness(_ percent: Int, for displayID: CGDirectDisplayID, isBuiltIn: Bool, externalIndex: Int) {
        let clamped = min(max(percent, 0), 100)
        lock.lock()
        cachedBrightness[displayID] = clamped
        lock.unlock()
        
        if isBuiltIn {
            _ = dsSetBrightness?(displayID, Float(clamped) / 100.0)
        } else {
            ddcQueue.async { [weak self] in
                self?.writeDDC(vcp: Self.vcpBrightness, value: UInt16(clamped), externalIndex: externalIndex)
            }
        }
    }
    
    public func setVolume(_ percent: Int, for displayID: CGDirectDisplayID, externalIndex: Int) {
        let clamped = min(max(percent, 0), 100)
        lock.lock()
        cachedVolume[displayID] = clamped
        lock.unlock()
        
        ddcQueue.async { [weak self] in
            self?.writeDDC(vcp: Self.vcpVolume, value: UInt16(clamped), externalIndex: externalIndex)
        }
    }
    
    // MARK: - Helpers
    
    private func readBuiltInBrightness(_ displayID: CGDirectDisplayID) -> Int? {
        guard let fn = dsGetBrightness else { return nil }
        var val: Float = 0.0
        guard fn(displayID, &val) == 0 else { return nil }
        return min(max(Int((val * 100.0).rounded()), 0), 100)
    }
    
    private func cachedBrightnessValue(for displayID: CGDirectDisplayID, default fallback: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return cachedBrightness[displayID] ?? fallback
    }
    
    private func cachedVolumeValue(for displayID: CGDirectDisplayID, default fallback: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return cachedVolume[displayID] ?? fallback
    }
    
    /// Discovers Apple Silicon external display AVService proxies via IORegistry.
    private func discoverExternalAVServices() -> [CFTypeRef] {
        guard let createFn = avCreateWithService else { return [] }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        
        var services: [CFTypeRef] = []
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = props?.takeRetainedValue() as? [String: Any],
               let location = dict["Location"] as? String,
               location == "External" {
                if let av = createFn(kCFAllocatorDefault, entry)?.takeRetainedValue() {
                    services.append(av)
                }
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        return services
    }
    
    private func writeDDC(vcp: UInt8, value: UInt16, externalIndex: Int) {
        guard let writeFn = avWriteI2C else { return }
        let services = discoverExternalAVServices()
        guard externalIndex >= 0, externalIndex < services.count else { return }
        let service = services[externalIndex]
        
        let highByte = UInt8((value >> 8) & 0xFF)
        let lowByte = UInt8(value & 0xFF)
        var packet: [UInt8] = [0x84, 0x03, vcp, highByte, lowByte, 0x00]
        var checksum: UInt8 = 0x6E ^ 0x51
        for i in 0..<5 { checksum ^= packet[i] }
        packet[5] = checksum
        
        for _ in 0..<2 {
            let kr = writeFn(service, 0x37, 0x51, &packet, UInt32(packet.count))
            if kr == KERN_SUCCESS { break }
            usleep(10_000)
        }
    }
}
