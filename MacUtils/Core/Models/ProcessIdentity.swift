import Foundation
import Darwin

/// Resolves a raw pid into a user-facing identity: the owning .app's display name and path
/// (so Chrome helpers, renderers, etc. group under "Google Chrome"), or a cleaned-up binary name.
public struct ProcessIdentity: Sendable {
    public let key: String        // grouping key
    public let name: String       // full, untruncated display name
    public let iconPath: String?  // path handed to NSWorkspace for the icon (.app bundle or executable)
    
    public static func resolve(pid: Int32, fallbackName: String) -> ProcessIdentity {
        var buf = [CChar](repeating: 0, count: 4 * 1024)
        let len = proc_pidpath(pid, &buf, UInt32(buf.count))
        let path = len > 0 ? String(cString: buf) : nil
        
        if let path, let appPath = outermostAppPath(in: path) {
            return ProcessIdentity(key: appPath, name: bundleName(at: appPath), iconPath: appPath)
        }
        return ProcessIdentity(key: path ?? fallbackName, name: cleanName(fallbackName, path: path), iconPath: path)
    }
    
    private static func outermostAppPath(in path: String) -> String? {
        let comps = path.split(separator: "/", omittingEmptySubsequences: true)
        guard let idx = comps.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
        return "/" + comps[...idx].joined(separator: "/")
    }
    
    // Reading Info.plist hits the disk, and resolve() runs for every process on every tick.
    nonisolated(unsafe) private static var nameCache: [String: String] = [:]
    private static let nameCacheLock = NSLock()
    
    private static func bundleName(at appPath: String) -> String {
        nameCacheLock.lock()
        defer { nameCacheLock.unlock() }
        if let cached = nameCache[appPath] { return cached }
        let name = readBundleName(at: appPath)
        nameCache[appPath] = name
        return name
    }
    
    private static func readBundleName(at appPath: String) -> String {
        let info = Bundle(path: appPath)?.infoDictionary
        if let n = info?["CFBundleDisplayName"] as? String, !n.isEmpty { return n }
        if let n = info?["CFBundleName"] as? String, !n.isEmpty { return n }
        return ((appPath as NSString).lastPathComponent as NSString).deletingPathExtension
    }
    
    /// proc_name is capped at 16 chars and versioned binaries (".../claude/versions/2.1.277") are named
    /// after their version, so prefer the full executable name and skip version-looking components.
    private static func cleanName(_ name: String, path: String?) -> String {
        guard let path else { return name }
        let comps = path.split(separator: "/").map(String.init)
        func isVersion(_ s: String) -> Bool { !s.isEmpty && s.allSatisfy { $0.isNumber || $0 == "." } }
        if let last = comps.last, !isVersion(last) { return last }
        if let good = comps.dropLast().last(where: { !isVersion($0) && $0 != "versions" && $0 != "bin" }) { return good }
        return name
    }
}
