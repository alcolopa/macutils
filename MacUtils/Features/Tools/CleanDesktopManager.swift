import Foundation
import AppKit

public final class CleanDesktopManager: @unchecked Sendable {
    public static let shared = CleanDesktopManager()
    public static let didChange = Notification.Name("MacUtilsCleanDesktopDidChange")
    
    private let keyFinderCreateDesktop = "CreateDesktop"
    private let finderDomain = "com.apple.finder"
    
    public init() {}
    
    public var areIconsHidden: Bool {
        // When CreateDesktop is false, desktop icons are hidden
        let val = UserDefaults(suiteName: finderDomain)?.object(forKey: keyFinderCreateDesktop)
        if let boolVal = val as? Bool {
            return !boolVal
        }
        return false
    }
    
    public func setIconsHidden(_ hidden: Bool) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["write", finderDomain, keyFinderCreateDesktop, "-bool", hidden ? "false" : "true"]
        
        do {
            try process.run()
            process.waitUntilExit()
            
            // Restart Finder quietly to apply
            let killProc = Process()
            killProc.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            killProc.arguments = ["Finder"]
            try? killProc.run()
            killProc.waitUntilExit()
            
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.didChange, object: nil)
            }
        } catch {
            print("Failed to update desktop icon setting: \(error)")
        }
    }
    
    public func toggle() {
        setIconsHidden(!areIconsHidden)
    }
}
