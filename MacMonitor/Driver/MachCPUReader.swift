import Foundation
import Darwin

public final class MachCPUReader: @unchecked Sendable {
    private static let hostPort: mach_port_t = mach_host_self()
    
    private struct CoreTicks {
        var user: UInt64
        var system: UInt64
        var idle: UInt64
        var nice: UInt64
    }
    
    private var previousCoreTicks: [CoreTicks] = []
    private let lock = NSLock()
    
    // Cached CPU model name
    private static let cpuBrandString: String = {
        var cpuBrand = [CChar](repeating: 0, count: 128)
        var brandSize = cpuBrand.count
        if sysctlbyname("machdep.cpu.brand_string", &cpuBrand, &brandSize, nil, 0) == 0 {
            let str = String(cString: cpuBrand).trimmingCharacters(in: .whitespacesAndNewlines)
            if !str.isEmpty { return str }
        }
        return "Apple Silicon"
    }()
    
    public init() {}
    
    public func readSystemUsage(topProcesses: [ProcessItem] = []) -> CPUStats {
        lock.lock()
        defer { lock.unlock() }
        
        var processorCount: natural_t = 0
        var processorInfo: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        
        let result = host_processor_info(
            Self.hostPort,
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &processorInfo,
            &infoCount
        )
        
        // System Load Averages
        var loadavg = [Double](repeating: 0.0, count: 3)
        getloadavg(&loadavg, 3)
        
        // System Uptime
        var bootTime = timeval()
        var btSize = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        var uptime: Double = 0.0
        if sysctl(&mib, 2, &bootTime, &btSize, nil, 0) == 0 {
            uptime = max(0, Date().timeIntervalSince1970 - Double(bootTime.tv_sec))
        }
        
        let now = mach_absolute_time()
        
        guard result == KERN_SUCCESS, let processorInfo = processorInfo else {
            return CPUStats(
                totalUsage: 0.0,
                perCoreLoads: [],
                loadAverages: loadavg,
                cpuModel: Self.cpuBrandString,
                uptimeSeconds: uptime,
                topProcesses: topProcesses,
                timestamp: now
            )
        }
        
        defer {
            let deallocSize = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: processorInfo)), deallocSize)
        }
        
        let count = Int(processorCount)
        var currentTicks: [CoreTicks] = []
        currentTicks.reserveCapacity(count)
        
        for i in 0..<count {
            let offset = i * Int(CPU_STATE_MAX)
            let user = UInt64(processorInfo[offset + Int(CPU_STATE_USER)])
            let system = UInt64(processorInfo[offset + Int(CPU_STATE_SYSTEM)])
            let idle = UInt64(processorInfo[offset + Int(CPU_STATE_IDLE)])
            let nice = UInt64(processorInfo[offset + Int(CPU_STATE_NICE)])
            currentTicks.append(CoreTicks(user: user, system: system, idle: idle, nice: nice))
        }
        
        guard previousCoreTicks.count == count else {
            previousCoreTicks = currentTicks
            let loads = (0..<count).map { CoreLoad(coreIndex: $0, userPercentage: 0.0, systemPercentage: 0.0, idlePercentage: 100.0) }
            return CPUStats(
                totalUsage: 0.0,
                perCoreLoads: loads,
                loadAverages: loadavg,
                cpuModel: Self.cpuBrandString,
                uptimeSeconds: uptime,
                topProcesses: topProcesses,
                timestamp: now
            )
        }
        
        var perCoreLoads: [CoreLoad] = []
        perCoreLoads.reserveCapacity(count)
        
        var totalActiveDelta: Double = 0.0
        var totalTotalDelta: Double = 0.0
        
        for i in 0..<count {
            let prev = previousCoreTicks[i]
            let curr = currentTicks[i]
            
            let userDelta = Double(curr.user >= prev.user ? curr.user - prev.user : 0)
            let sysDelta = Double(curr.system >= prev.system ? curr.system - prev.system : 0)
            let niceDelta = Double(curr.nice >= prev.nice ? curr.nice - prev.nice : 0)
            let idleDelta = Double(curr.idle >= prev.idle ? curr.idle - prev.idle : 0)
            
            let activeDelta = userDelta + sysDelta + niceDelta
            let totalDelta = activeDelta + idleDelta
            
            totalActiveDelta += activeDelta
            totalTotalDelta += totalDelta
            
            let userPct = totalDelta > 0.0 ? ((userDelta + niceDelta) / totalDelta) * 100.0 : 0.0
            let sysPct = totalDelta > 0.0 ? (sysDelta / totalDelta) * 100.0 : 0.0
            let idlePct = totalDelta > 0.0 ? (idleDelta / totalDelta) * 100.0 : 100.0
            
            perCoreLoads.append(CoreLoad(
                coreIndex: i,
                userPercentage: min(max(userPct, 0.0), 100.0),
                systemPercentage: min(max(sysPct, 0.0), 100.0),
                idlePercentage: min(max(idlePct, 0.0), 100.0)
            ))
        }
        
        previousCoreTicks = currentTicks
        let totalUsage = totalTotalDelta > 0.0 ? min(max((totalActiveDelta / totalTotalDelta) * 100.0, 0.0), 100.0) : 0.0
        
        return CPUStats(
            totalUsage: totalUsage,
            perCoreLoads: perCoreLoads,
            loadAverages: loadavg,
            cpuModel: Self.cpuBrandString,
            uptimeSeconds: uptime,
            topProcesses: topProcesses,
            timestamp: now
        )
    }
}
