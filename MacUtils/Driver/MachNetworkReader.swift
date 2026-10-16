import Foundation
import Darwin

public final class MachNetworkReader: @unchecked Sendable {
    private struct InterfaceSnapshot {
        var bytesIn: UInt64
        var bytesOut: UInt64
        var timestamp: UInt64
    }
    
    private struct ProcessNetSnapshot {
        var bytesIn: UInt64
        var bytesOut: UInt64
        var timestamp: UInt64
    }
    
    private var lastSnapshot: InterfaceSnapshot?
    private var lastProcSnapshots: [Int32: ProcessNetSnapshot] = [:]
    private var peakIn: Double = 0.0
    private var peakOut: Double = 0.0
    private let lock = NSLock()
    
    public init() {}
    
    public func readTopNetworkProcesses(limit: Int = 5) -> [NetworkProcessItem] {
        lock.lock()
        defer { lock.unlock() }
        
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        process.arguments = ["-P", "-L", "1", "-J", "bytes_in,bytes_out", "-x"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            
            guard let text = String(data: data, encoding: .utf8) else {
                return []
            }
            
            let now = mach_absolute_time()
            var timebase = mach_timebase_info()
            mach_timebase_info(&timebase)
            
            var currentProcs: [NetworkProcessItem] = []
            var newProcSnapshots: [Int32: ProcessNetSnapshot] = [:]
            
            let lines = text.split(separator: "\n")
            for line in lines {
                let parts = line.split(separator: ",", omittingEmptySubsequences: false)
                guard parts.count >= 3 else { continue }
                
                let rawProc = parts[0].trimmingCharacters(in: .whitespaces)
                guard !rawProc.isEmpty, rawProc != "time" else { continue }
                
                guard let lastDot = rawProc.lastIndex(of: "."),
                      let pid = Int32(rawProc[rawProc.index(after: lastDot)...]) else {
                    continue
                }
                
                let name = String(rawProc[..<lastDot])
                guard let bIn = UInt64(parts[1].trimmingCharacters(in: .whitespaces)),
                      let bOut = UInt64(parts[2].trimmingCharacters(in: .whitespaces)) else {
                    continue
                }
                
                // Only track processes that have transferred data
                if bIn == 0 && bOut == 0 { continue }
                
                var inRate: Double = 0.0
                var outRate: Double = 0.0
                
                if let prev = lastProcSnapshots[pid] {
                    let elapsedNanos = (now - prev.timestamp) * UInt64(timebase.numer) / UInt64(timebase.denom)
                    let elapsedSec = Double(elapsedNanos) / 1_000_000_000.0
                    if elapsedSec > 0.05 {
                        let deltaIn = bIn >= prev.bytesIn ? bIn - prev.bytesIn : 0
                        let deltaOut = bOut >= prev.bytesOut ? bOut - prev.bytesOut : 0
                        inRate = Double(deltaIn) / elapsedSec
                        outRate = Double(deltaOut) / elapsedSec
                    }
                }
                
                newProcSnapshots[pid] = ProcessNetSnapshot(bytesIn: bIn, bytesOut: bOut, timestamp: now)
                
                currentProcs.append(NetworkProcessItem(
                    pid: pid,
                    name: name,
                    bytesInPerSec: inRate,
                    bytesOutPerSec: outRate,
                    totalBytesIn: bIn,
                    totalBytesOut: bOut
                ))
            }
            
            lastProcSnapshots = newProcSnapshots
            
            var grouped: [String: NetworkProcessItem] = [:]
            for p in currentProcs {
                let id = ProcessIdentity.resolve(pid: p.pid, fallbackName: p.name)
                if let g = grouped[id.key] {
                    grouped[id.key] = NetworkProcessItem(pid: g.pid, name: g.name,
                        bytesInPerSec: g.bytesInPerSec + p.bytesInPerSec, bytesOutPerSec: g.bytesOutPerSec + p.bytesOutPerSec,
                        totalBytesIn: g.totalBytesIn + p.totalBytesIn, totalBytesOut: g.totalBytesOut + p.totalBytesOut, iconPath: g.iconPath)
                } else {
                    grouped[id.key] = NetworkProcessItem(pid: p.pid, name: id.name,
                        bytesInPerSec: p.bytesInPerSec, bytesOutPerSec: p.bytesOutPerSec,
                        totalBytesIn: p.totalBytesIn, totalBytesOut: p.totalBytesOut, iconPath: id.iconPath)
                }
            }
            currentProcs = Array(grouped.values)
            
            // Prioritize apps with active throughput first; if none, sort by total data transferred
            let sorted = currentProcs.sorted { a, b in
                let speedA = a.bytesInPerSec + a.bytesOutPerSec
                let speedB = b.bytesInPerSec + b.bytesOutPerSec
                if speedA > 0.05 || speedB > 0.05 {
                    return speedA > speedB
                }
                return (a.totalBytesIn + a.totalBytesOut) > (b.totalBytesIn + b.totalBytesOut)
            }
            
            return Array(sorted.prefix(limit))
        } catch {
            return []
        }
    }
    
    public func readNetworkUsage(topProcesses: [NetworkProcessItem] = []) -> NetworkStats {
        lock.lock()
        defer { lock.unlock() }
        
        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        var primaryName = "en0"
        var localIP = "127.0.0.1"
        
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else {
            let now = mach_absolute_time()
            return NetworkStats(bytesInPerSec: 0, bytesOutPerSec: 0, totalBytesIn: 0, totalBytesOut: 0, primaryInterface: primaryName, localIPAddress: localIP, topProcesses: topProcesses, timestamp: now)
        }
        
        defer {
            freeifaddrs(first)
        }
        
        var cur: UnsafeMutablePointer<ifaddrs>? = first
        while let ptr = cur {
            let name = String(cString: ptr.pointee.ifa_name)
            let family = ptr.pointee.ifa_addr?.pointee.sa_family ?? 0
            
            // Extract local IPv4 address
            if family == UInt8(AF_INET) && name == "en0" {
                var addr = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(ptr.pointee.ifa_addr, socklen_t(ptr.pointee.ifa_addr.pointee.sa_len),
                            &addr, socklen_t(addr.count), nil, 0, NI_NUMERICHOST)
                let ipStr = String(cString: addr)
                if !ipStr.isEmpty && ipStr != "127.0.0.1" {
                    localIP = ipStr
                }
            }
            
            if family == UInt8(AF_LINK) {
                if !name.hasPrefix("lo") && !name.hasPrefix("gif") && !name.hasPrefix("stf") {
                    let data = ptr.pointee.ifa_data.assumingMemoryBound(to: if_data.self)
                    let ibytes = UInt64(data.pointee.ifi_ibytes)
                    let obytes = UInt64(data.pointee.ifi_obytes)
                    
                    if name == "en0" && (ibytes > 0 || obytes > 0) {
                        primaryName = "en0"
                    }
                    
                    totalIn += ibytes
                    totalOut += obytes
                }
            }
            cur = ptr.pointee.ifa_next
        }
        
        let now = mach_absolute_time()
        
        guard let prev = lastSnapshot else {
            lastSnapshot = InterfaceSnapshot(bytesIn: totalIn, bytesOut: totalOut, timestamp: now)
            return NetworkStats(
                bytesInPerSec: 0,
                bytesOutPerSec: 0,
                totalBytesIn: totalIn,
                totalBytesOut: totalOut,
                primaryInterface: primaryName,
                localIPAddress: localIP,
                peakBytesInPerSec: 0,
                peakBytesOutPerSec: 0,
                topProcesses: topProcesses,
                timestamp: now
            )
        }
        
        var timebase = mach_timebase_info()
        mach_timebase_info(&timebase)
        let elapsedNanos = (now - prev.timestamp) * UInt64(timebase.numer) / UInt64(timebase.denom)
        let elapsedSec = Double(elapsedNanos) / 1_000_000_000.0
        
        let inDelta = totalIn >= prev.bytesIn ? totalIn - prev.bytesIn : 0
        let outDelta = totalOut >= prev.bytesOut ? totalOut - prev.bytesOut : 0
        
        var inPerSec: Double = 0
        var outPerSec: Double = 0
        if elapsedSec > 0.05 {
            inPerSec = Double(inDelta) / elapsedSec
            outPerSec = Double(outDelta) / elapsedSec
        }
        
        peakIn = max(peakIn, inPerSec)
        peakOut = max(peakOut, outPerSec)
        
        lastSnapshot = InterfaceSnapshot(bytesIn: totalIn, bytesOut: totalOut, timestamp: now)
        
        return NetworkStats(
            bytesInPerSec: inPerSec,
            bytesOutPerSec: outPerSec,
            totalBytesIn: totalIn,
            totalBytesOut: totalOut,
            primaryInterface: primaryName,
            localIPAddress: localIP,
            peakBytesInPerSec: peakIn,
            peakBytesOutPerSec: peakOut,
            topProcesses: topProcesses,
            timestamp: now
        )
    }
}
