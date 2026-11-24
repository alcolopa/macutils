import AppKit
import Carbon.HIToolbox

/// A global hotkey: Carbon key code + Carbon modifiers, plus the typed character for menu hints.
public struct Shortcut: Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    public var character: String
    
    public init(keyCode: Int, modifiers: Int, character: String) {
        self.keyCode = UInt32(keyCode)
        self.modifiers = UInt32(modifiers)
        self.character = character
    }
    
    init?(event: NSEvent) {
        var mods = 0
        let f = event.modifierFlags
        if f.contains(.command) { mods |= cmdKey }
        if f.contains(.shift) { mods |= shiftKey }
        if f.contains(.option) { mods |= optionKey }
        if f.contains(.control) { mods |= controlKey }
        guard mods != 0 else { return nil }   // a bare key would hijack typing everywhere
        self.init(keyCode: Int(event.keyCode), modifiers: mods, character: event.charactersIgnoringModifiers?.lowercased() ?? "")
    }
    
    var stored: String { "\(keyCode),\(modifiers),\(character)" }
    
    init?(stored: String) {
        let p = stored.split(separator: ",", maxSplits: 2, omittingEmptySubsequences: false)
        guard p.count == 3, let k = Int(p[0]), let m = Int(p[1]) else { return nil }
        self.init(keyCode: k, modifiers: m, character: String(p[2]))
    }
    
    /// NSEvent flags equivalent of `modifiers`.
    var flags: NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if modifiers & UInt32(cmdKey) != 0 { f.insert(.command) }
        if modifiers & UInt32(shiftKey) != 0 { f.insert(.shift) }
        if modifiers & UInt32(optionKey) != 0 { f.insert(.option) }
        if modifiers & UInt32(controlKey) != 0 { f.insert(.control) }
        return f
    }
    
    private static let specialNames: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12"
    ]
    
    /// The key's unshifted character on the current layout (stored text can be shifted, e.g. "@" for 2).
    private var keyText: String {
        guard let src = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else { return character }
        let layout = unsafeBitCast(raw, to: CFData.self)
        var dead: UInt32 = 0, len = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = CFDataGetBytePtr(layout).withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) {
            UCKeyTranslate($0, UInt16(keyCode), UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                           OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &len, &chars)
        }
        return status == noErr && len > 0 ? String(utf16CodeUnits: chars, count: len).lowercased() : character
    }
    
    public var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + (Self.specialNames[Int(keyCode)] ?? keyText.uppercased())
    }
    
    /// Character for an NSMenuItem hint; empty for keys that have no plain character.
    public var keyEquivalent: String { Self.specialNames[Int(keyCode)] == nil ? keyText : "" }
}

/// Click, then press the new combination (needs at least one modifier). Esc cancels.
@MainActor
final class ShortcutRecorderButton: NSButton {
    var onChange: ((Shortcut) -> Void)?
    private(set) var shortcut: Shortcut
    private var monitor: Any?
    
    init(shortcut: Shortcut) {
        self.shortcut = shortcut
        super.init(frame: .zero)
        bezelStyle = .rounded
        font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        target = self
        action = #selector(toggleRecording)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 110).isActive = true
        title = shortcut.display
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    func set(_ new: Shortcut) {
        shortcut = new
        if monitor == nil { title = new.display }
    }
    
    @objc private func toggleRecording() {
        monitor == nil ? beginRecording() : endRecording()
    }
    
    private func beginRecording() {
        title = "Press keys…"
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == UInt16(kVK_Escape) { self.endRecording() }
            else if let new = Shortcut(event: event) {
                self.shortcut = new
                self.endRecording()
                self.onChange?(new)
            }
            return nil
        }
    }
    
    private func endRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        title = shortcut.display
    }
}
