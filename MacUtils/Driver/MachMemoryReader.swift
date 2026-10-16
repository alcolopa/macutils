import Foundation
import Darwin

public final class MachMemoryReader: @unchecked Sendable {
    private static let hostPort: mach_port_t = mach_host_self()
    
    private static let pageSize: UInt64 = {
        var pSize: vm_size_t = 0
        let kr = host_page_size(mach_host_self(), &pSize)
        if kr == KERN_SUCCESS && pSize > 0 {
            return UInt64(pSize)
        }
        return UInt64(getpagesize())
    }()
    
    public init() {}
    
    public func readMemoryUsage(topProcesses: [ProcessItem] = []) -> MemoryStats {
        var hostInfoCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var vmStats = vm_statistics64()
        
        let result = withUnsafeMutablePointer(to: &vmStats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(hostInfoCount)) { intPtr in
                host_statistics64(Self.hostPort, HOST_VM_INFO64, intPtr, &hostInfoCount)
            }
        }
        
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        let swap = readSwapUsage()
        let (pressureState, pressurePct) = readMemoryPressure()
        
        guard result == KERN_SUCCESS else {
            return MemoryStats(
                totalBytes: totalBytes,
                freeBytes: 0,
                activeBytes: 0,
                inactiveBytes: 0,
                wiredBytes: 0,
                compressedBytes: 0,
                purgeableBytes: 0,
                swap: swap,
                pressureState: pressureState,
                pressurePercentage: pressurePct,
                topProcesses: topProcesses
            )
        }
        
        let pageSize = Self.pageSize
        let freeBytes = UInt64(vmStats.free_count) * pageSize
        let activeBytes = UInt64(vmStats.active_count) * pageSize
        let inactiveBytes = UInt64(vmStats.inactive_count) * pageSize
        let wiredBytes = UInt64(vmStats.wire_count) * pageSize
        let compressedBytes = UInt64(vmStats.compressor_page_count) * pageSize
        let purgeableBytes = UInt64(vmStats.purgeable_count) * pageSize
        
        return MemoryStats(
            totalBytes: totalBytes,
            freeBytes: freeBytes,
            activeBytes: activeBytes,
            inactiveBytes: inactiveBytes,
            wiredBytes: wiredBytes,
            compressedBytes: compressedBytes,
            purgeableBytes: purgeableBytes,
            swap: swap,
            pressureState: pressureState,
            pressurePercentage: pressurePct,
            topProcesses: topProcesses
        )
    }
    
    private func readSwapUsage() -> SwapStats {
        var mib: [Int32] = [CTL_VM, VM_SWAPUSAGE]
        var swapUsage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        
        let result = sysctl(&mib, 2, &swapUsage, &size, nil, 0)
        guard result == 0 else {
            return SwapStats(totalBytes: 0, usedBytes: 0, freeBytes: 0)
        }
        
        return SwapStats(
            totalBytes: UInt64(swapUsage.xsu_total),
            usedBytes: UInt64(swapUsage.xsu_used),
            freeBytes: UInt64(swapUsage.xsu_avail)
        )
    }
    
    private func readMemoryPressure() -> (MemoryPressureState, Double) {
        var pressureLevel: Int32 = 0
        var size = MemoryLayout<Int32>.size
        
        // kern.memorystatus_vm_pressure_level:
        // 1: Normal, 2: Warning, 4: Critical
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &pressureLevel, &size, nil, 0) == 0 {
            switch pressureLevel {
            case 4:
                return (.critical, 90.0)
            case 2:
                return (.warning, 65.0)
            default:
                return (.normal, 25.0)
            }
        }
        return (.normal, 20.0)
    }
}
