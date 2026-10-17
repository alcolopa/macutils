import Foundation
import Darwin

public final class DarwinProcessReader: @unchecked Sendable {
    private struct ProcTicks {
        var user: UInt64
        var system: UInt64
        var timestamp: UInt64
    }
    
    private var previousTicks: [pid_t: ProcTicks] = [:]
    private let lock = NSLock()
    
    public init() {}
    
    private var lastReadTime: Date?
    
    public func readTopProcesses(limit: Int = 5) -> (byMemory: [ProcessItem], byCPU: [ProcessItem]) {
        // CPU % is a delta between two reads. If the last read is stale (popover was closed),
        // prime a baseline and sample again shortly so the first display isn't all zeros.
        lock.lock()
        let stale = lastReadTime.map { Date().timeIntervalSince($0) > 2.0 } ?? true
        lock.unlock()
        if stale {
            _ = sample(limit: limit)
            Thread.sleep(forTimeInterval: 0.25)
        }
        return sample(limit: limit)
    }
    
    private func sample(limit: Int) -> (byMemory: [ProcessItem], byCPU: [ProcessItem]) {
        lock.lock()
        defer { lock.unlock() }
        
        lastReadTime = Date()
        let now = mach_absolute_time()
        var timebase = mach_timebase_info()
        mach_timebase_info(&timebase)
        
        var pids = [pid_t](repeating: 0, count: 4096)
        let bytes = proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.stride * pids.count))
        let pidCount = max(0, Int(bytes) / MemoryLayout<pid_t>.stride)
        
        var currentTicks: [pid_t: ProcTicks] = [:]
        var items: [ProcessItem] = []
        items.reserveCapacity(pidCount)
        
        var nameBuf = [CChar](repeating: 0, count: 128)
        let infoSize = Int32(MemoryLayout<proc_taskinfo>.stride)
        
        for i in 0..<pidCount {
            let pid = pids[i]
            if pid <= 0 { continue }
            
            let len = proc_name(pid, &nameBuf, UInt32(nameBuf.count))
            if len > 0 {
                var procInfo = proc_taskinfo()
                let ret = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &procInfo, infoSize)
                if ret == infoSize {
                    let name = String(decoding: nameBuf.prefix(Int(len)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
                    let resident = UInt64(procInfo.pti_resident_size)
                    let userTime = UInt64(procInfo.pti_total_user)
                    let sysTime = UInt64(procInfo.pti_total_system)
                    
                    var cpuPct: Double = 0.0
                    if let prev = previousTicks[pid] {
                        let totalPrev = prev.user + prev.system
                        let totalCurr = userTime + sysTime
                        if totalCurr >= totalPrev && now > prev.timestamp {
                            let deltaTicks = totalCurr - totalPrev
                            let deltaNanos = (now - prev.timestamp) * UInt64(timebase.numer) / UInt64(timebase.denom)
                            if deltaNanos > 0 {
                                cpuPct = (Double(deltaTicks) / Double(deltaNanos)) * 100.0
                            }
                        }
                    }
                    
                    currentTicks[pid] = ProcTicks(user: userTime, system: sysTime, timestamp: now)
                    items.append(ProcessItem(pid: pid, name: name, residentBytes: resident, cpuPercentage: cpuPct, userTimeNanos: userTime))
                }
            }
        }
        
        previousTicks = currentTicks
        
        // Group helper processes under their owning app (Chrome + its renderers → "Google Chrome")
        var groups: [String: ProcessItem] = [:]
        var groupBest: [String: UInt64] = [:]
        for item in items {
            let id = ProcessIdentity.resolve(pid: item.pid, fallbackName: item.name)
            if let g = groups[id.key] {
                let leadPid = item.residentBytes > (groupBest[id.key] ?? 0) ? item.pid : g.pid
                groupBest[id.key] = max(groupBest[id.key] ?? 0, item.residentBytes)
                groups[id.key] = ProcessItem(pid: leadPid, name: g.name, residentBytes: g.residentBytes + item.residentBytes,
                                             cpuPercentage: g.cpuPercentage + item.cpuPercentage,
                                             userTimeNanos: g.userTimeNanos + item.userTimeNanos, iconPath: g.iconPath)
            } else {
                groupBest[id.key] = item.residentBytes
                groups[id.key] = ProcessItem(pid: item.pid, name: id.name, residentBytes: item.residentBytes,
                                             cpuPercentage: item.cpuPercentage, userTimeNanos: item.userTimeNanos, iconPath: id.iconPath)
            }
        }
        items = Array(groups.values)
        
        // Sort top by resident memory
        let topMem = items.sorted { $0.residentBytes > $1.residentBytes }.prefix(limit)
        // Sort top by live differential CPU %
        let topCPU = items.sorted { $0.cpuPercentage > $1.cpuPercentage }.prefix(limit)
        
        return (Array(topMem), Array(topCPU))
    }
}
