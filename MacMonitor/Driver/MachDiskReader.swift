import Foundation
import Darwin

public final class MachDiskReader: @unchecked Sendable {
    public init() {}
    
    public func readDiskUsage() -> DiskStats {
        var stat = statvfs()
        var rootVol = VolumeInfo(name: "Macintosh HD", mountPoint: "/", totalBytes: 0, usedBytes: 0, freeBytes: 0)
        
        if statvfs("/", &stat) == 0 {
            let bsize = UInt64(stat.f_frsize)
            let total = UInt64(stat.f_blocks) * bsize
            let free = UInt64(stat.f_bfree) * bsize
            let avail = UInt64(stat.f_bavail) * bsize
            let used = total >= free ? total - free : 0
            
            rootVol = VolumeInfo(
                name: "Macintosh HD",
                mountPoint: "/",
                totalBytes: total,
                usedBytes: used,
                freeBytes: avail
            )
        }
        
        var volumes: [VolumeInfo] = [rootVol]
        
        // Query mounted filesystems via getmntinfo
        var mntbuf: UnsafeMutablePointer<statfs>?
        let count = getmntinfo(&mntbuf, MNT_NOWAIT)
        if count > 0, let mntbuf = mntbuf {
            for i in 0..<Int(count) {
                let s = mntbuf[i]
                let mntOn = withUnsafePointer(to: s.f_mntonname) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MNAMELEN)) { String(cString: $0) }
                }
                let mntFrom = withUnsafePointer(to: s.f_mntfromname) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MNAMELEN)) { String(cString: $0) }
                }
                
                // Only consider real disk partitions (typically /dev/disk*) and non-root mounts
                if mntFrom.hasPrefix("/dev/disk") && mntOn != "/" {
                    let bsize = UInt64(s.f_bsize)
                    let total = UInt64(s.f_blocks) * bsize
                    let free = UInt64(s.f_bfree) * bsize
                    let avail = UInt64(s.f_bavail) * bsize
                    let used = total >= free ? total - free : 0
                    
                    let name = (mntOn as NSString).lastPathComponent
                    volumes.append(VolumeInfo(
                        name: name.isEmpty ? mntOn : name,
                        mountPoint: mntOn,
                        totalBytes: total,
                        usedBytes: used,
                        freeBytes: avail
                    ))
                }
            }
        }
        
        return DiskStats(
            rootVolume: rootVol,
            allVolumes: volumes,
            timestamp: mach_absolute_time()
        )
    }
}
