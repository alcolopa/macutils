import Foundation
import AppKit

public final class DarwinPortReader: @unchecked Sendable {
    public static let shared = DarwinPortReader()
    private let lock = NSLock()
    private var cachedPorts: [ListeningPortItem] = []
    private var lastFetch: Date?
    
    public init() {}
    
    public func readListeningPorts(forceRefresh: Bool = false) -> [ListeningPortItem] {
        lock.lock()
        if !forceRefresh, let last = lastFetch, Date().timeIntervalSince(last) < 2.0 {
            let res = cachedPorts
            lock.unlock()
            return res
        }
        lock.unlock()
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return []
            }
            
            var items: [ListeningPortItem] = []
            var seen = Set<String>()
            let lines = output.components(separatedBy: .newlines)
            
            for line in lines.dropFirst() {
                let parts = line.split(whereSeparator: { $0.isWhitespace })
                guard parts.count >= 9 else { continue }
                
                let rawCommand = String(parts[0])
                guard let pid = Int32(parts[1]) else { continue }
                let nameField = String(parts[8]) // e.g. "*:3000" or "127.0.0.1:8080"
                
                // Parse port
                guard let colonIdx = nameField.lastIndex(of: ":") else { continue }
                let hostPart = String(nameField[..<colonIdx])
                let portPart = String(nameField[nameField.index(after: colonIdx)...])
                guard let port = Int(portPart) else { continue }
                
                let key = "\(port)-\(pid)"
                if seen.insert(key).inserted {
                    let id = ProcessIdentity.resolve(pid: pid, fallbackName: rawCommand)
                    items.append(ListeningPortItem(
                        port: port,
                        pid: pid,
                        processName: id.name,
                        address: hostPart.isEmpty ? "*" : hostPart,
                        iconPath: id.iconPath
                    ))
                }
            }
            
            items.sort { $0.port < $1.port }
            
            lock.lock()
            cachedPorts = items
            lastFetch = Date()
            lock.unlock()
            
            return items
        } catch {
            return []
        }
    }
    
    public func killProcess(pid: pid_t) -> Bool {
        guard pid > 1 else { return false }
        let ret = Darwin.kill(pid, SIGTERM)
        if ret != 0 {
            _ = Darwin.kill(pid, SIGKILL)
        }
        lock.lock()
        cachedPorts.removeAll { $0.pid == pid }
        lock.unlock()
        return true
    }
}
