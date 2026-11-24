import AppKit
import Carbon

/// Registers the Quick Tools global hotkeys through `GlobalHotKeys`.
@MainActor
public final class QuickToolsHotkeys {
    public static let shared = QuickToolsHotkeys()
    
    public struct ShortcutInfo: Sendable {
        public let id: UInt32
        public let title: String
        public let defaultShortcut: Shortcut
        
        public var name: String { "tool.\(id)" }
        @MainActor public var current: Shortcut { AppPreferences.shared.shortcut(name, default: defaultShortcut) }
    }
    
    public static let shortcuts: [ShortcutInfo] = [
        ShortcutInfo(id: 1, title: "Extract Text from Screen (OCR)", defaultShortcut: Shortcut(keyCode: kVK_ANSI_2, modifiers: cmdKey | shiftKey, character: "2")),
        ShortcutInfo(id: 2, title: "Pick Screen Color", defaultShortcut: Shortcut(keyCode: kVK_ANSI_X, modifiers: cmdKey | shiftKey, character: "x")),
        ShortcutInfo(id: 3, title: "Quick Scratchpad", defaultShortcut: Shortcut(keyCode: kVK_ANSI_N, modifiers: cmdKey | shiftKey, character: "n")),
        ShortcutInfo(id: 4, title: "Toggle Microphone Mute", defaultShortcut: Shortcut(keyCode: kVK_ANSI_M, modifiers: optionKey | shiftKey, character: "m")),
        ShortcutInfo(id: 5, title: "Toggle Clean Desktop", defaultShortcut: Shortcut(keyCode: kVK_ANSI_D, modifiers: cmdKey | shiftKey, character: "d"))
    ]
    
    @MainActor public static func current(id: UInt32) -> Shortcut {
        shortcuts.first { $0.id == id }!.current
    }
    
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var isStarted = false
    private var registered: [Shortcut] = []
    
    private init() {}
    
    public func start() {
        guard !isStarted else { return reloadIfNeeded() }
        isStarted = true
        registerAll()
    }
    
    private func registerAll() {
        hotKeyRefs.forEach { GlobalHotKeys.shared.unregister($0) }
        hotKeyRefs.removeAll()
        registered = Self.shortcuts.map(\.current)
        for (sc, key) in zip(Self.shortcuts, registered) {
            let id = sc.id
            if let ref = GlobalHotKeys.shared.register(keyCode: key.keyCode, modifiers: key.modifiers, action: { [weak self] in self?.handleHotKey(id: id) }) {
                hotKeyRefs.append(ref)
            }
        }
    }
    
    /// Called on every preference change; re-registers only when a shortcut was edited.
    public func reloadIfNeeded() {
        if isStarted, registered != Self.shortcuts.map(\.current) { registerAll() }
    }
    
    public func stop() {
        guard isStarted else { return }
        isStarted = false
        hotKeyRefs.forEach { GlobalHotKeys.shared.unregister($0) }
        hotKeyRefs.removeAll()
    }
    
    private func handleHotKey(id: UInt32) {
        switch id {
        case 1:
            ScreenTextExtractor.shared.extractTextFromScreen()
        case 2:
            ScreenColorPicker.shared.pickColor()
        case 3:
            ScratchpadWindowController.shared.showScratchpad()
        case 4:
            AudioHardwareManager.shared.toggleInputMute()
        case 5:
            CleanDesktopManager.shared.toggle()
        default:
            break
        }
    }
}
