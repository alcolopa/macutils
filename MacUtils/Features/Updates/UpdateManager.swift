import AppKit

/// Checks GitHub Releases for a newer MacUtils and can download and install it in place.
@MainActor
public final class UpdateManager {
    public static let shared = UpdateManager()
    public static let didChange = Notification.Name("MacUtilsUpdateDidChange")
    
    public struct Release: Sendable {
        public let version: String
        public let notes: String
        public let pageURL: URL
        public let zipURL: URL
    }
    
    public enum State {
        case idle
        case checking
        case upToDate
        case available(Release)
        case downloading(Double)
        case installing
        case failed(String)
    }
    
    private static let repo = "alcolopa/macutils"
    private static let lastCheckKey = "updateLastCheck"
    private static let notifiedKey = "updateNotifiedVersion"
    
    public private(set) var state: State = .idle { didSet { NotificationCenter.default.post(name: Self.didChange, object: nil) } }
    
    private init() {}
    
    public var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
    
    /// Updating replaces the app bundle, so it only works for the packaged app (not `swift run`).
    public var canInstall: Bool { Bundle.main.bundleURL.pathExtension == "app" }
    
    public var availableRelease: Release? {
        if case .available(let r) = state { return r }
        return nil
    }
    
    // MARK: - Checking
    
    /// Checks at most twice a day; shows an alert once per new version.
    public func checkInBackgroundIfDue() {
        guard AppPreferences.shared.autoCheckUpdates else { return }
        let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 12 * 3600 else { return }
        Task { await check(userInitiated: false) }
    }
    
    public func check(userInitiated: Bool = true) async {
        switch state {
        case .checking, .downloading, .installing: return
        default: break
        }
        state = .checking
        UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
        do {
            let release = try await Self.fetchLatest()
            if Self.isNewer(release.version, than: currentVersion) {
                state = .available(release)
                if !userInitiated { promptOnce(release) }
            } else {
                state = .upToDate
            }
        } catch {
            state = userInitiated ? .failed("Couldn't check for updates. Are you online?") : .idle
        }
    }
    
    private static func fetchLatest() async throws -> Release {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)),
              let assets = json["assets"] as? [[String: Any]],
              let zip = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".zip") == true }),
              let zipURL = (zip["browser_download_url"] as? String).flatMap(URL.init(string:))
        else { throw URLError(.badServerResponse) }
        return Release(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag,
                       notes: json["body"] as? String ?? "", pageURL: page, zipURL: zipURL)
    }
    
    /// Compares dotted numeric versions, e.g. "1.10.0" > "1.9.2".
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ v: String) -> [Int] { v.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 } }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
    
    private func promptOnce(_ release: Release) {
        guard UserDefaults.standard.string(forKey: Self.notifiedKey) != release.version else { return }
        UserDefaults.standard.set(release.version, forKey: Self.notifiedKey)
        let alert = NSAlert()
        alert.messageText = "MacUtils \(release.version) is available"
        alert.informativeText = "You have \(currentVersion)."
        alert.addButton(withTitle: canInstall ? "Install and Restart" : "View Release")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            if canInstall { install() } else { NSWorkspace.shared.open(release.pageURL) }
        }
    }
    
    // MARK: - Installing
    
    public func install() {
        guard let release = availableRelease, canInstall else { return }
        state = .downloading(0)
        Task {
            do {
                let appURL = try await download(release)
                state = .installing
                try startReplacement(with: appURL)
                NSApp.terminate(nil)
            } catch {
                state = .failed((error as? UpdateError)?.message ?? "The update couldn't be installed.")
            }
        }
    }
    
    private struct UpdateError: Error { let message: String }
    
    private func download(_ release: Release) async throws -> URL {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("MacUtilsUpdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let zip = work.appendingPathComponent("update.zip")
        FileManager.default.createFile(atPath: zip.path, contents: nil)
        
        let (bytes, response) = try await URLSession.shared.bytes(from: release.zipURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError(message: "The download failed.") }
        let total = Double(response.expectedContentLength)
        let handle = try FileHandle(forWritingTo: zip)
        var buffer = Data(), received = 0.0, lastReport = 0.0
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 65_536 {
                try handle.write(contentsOf: buffer)
                received += Double(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if total > 0, received / total - lastReport > 0.02 {
                    lastReport = received / total
                    state = .downloading(lastReport)
                }
            }
        }
        try handle.write(contentsOf: buffer)
        try handle.close()
        
        let extracted = work.appendingPathComponent("extracted")
        try await Task.detached { try Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, extracted.path]) }.value
        let apps = (try? FileManager.default.contentsOfDirectory(at: extracted, includingPropertiesForKeys: nil)) ?? []
        guard let app = apps.first(where: { $0.pathExtension == "app" }),
              Bundle(url: app)?.bundleIdentifier == Bundle.main.bundleIdentifier else {
            throw UpdateError(message: "The downloaded update wasn't a valid MacUtils.")
        }
        try await Task.detached { try Self.verifySignature(of: app) }.value
        return app
    }
    
    /// A new build must be signed by the same identity as this one, so a tampered download is refused.
    nonisolated private static func verifySignature(of newApp: URL) throws {
        let current = Bundle.main.bundleURL.path
        let requirement = try capture("/usr/bin/codesign", ["-d", "-r-", current])
        guard let line = requirement.split(separator: "\n").first(where: { $0.hasPrefix("designated =>") }),
              line.contains("certificate leaf") else { return }   // ad-hoc builds have nothing to compare
        let dr = String(line.dropFirst("designated => ".count))
        do { try run("/usr/bin/codesign", ["--verify", "--strict", "-R=\(dr)", newApp.path]) }
        catch { throw UpdateError(message: "The update isn't signed by the same developer, so it was not installed.") }
    }
    
    /// Swaps the app after we quit, then reopens it.
    private func startReplacement(with newApp: URL) throws {
        let dest = Bundle.main.bundleURL
        guard FileManager.default.isWritableFile(atPath: dest.deletingLastPathComponent().path) else {
            NSWorkspace.shared.activateFileViewerSelecting([newApp])
            throw UpdateError(message: "MacUtils can't replace itself in this folder. The new version was opened in Finder; drag it over the old one.")
        }
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("macutils-update.sh")
        let body = """
        #!/bin/bash
        while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
        rm -rf "$3.old"
        if mv "$3" "$3.old" && mv "$2" "$3"; then rm -rf "$3.old"; else mv "$3.old" "$3"; fi
        xattr -dr com.apple.quarantine "$3" 2>/dev/null
        open "$3"
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), newApp.path, dest.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
    
    nonisolated private static func run(_ path: String, _ args: [String]) throws {
        _ = try capture(path, args)
    }
    
    nonisolated private static func capture(_ path: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw UpdateError(message: "Command failed.") }
        return String(decoding: data, as: UTF8.self)
    }
}
