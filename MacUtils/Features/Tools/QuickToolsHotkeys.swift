import AppKit
import Carbon

/// Registers global system-wide hotkeys for Quick Tools using Carbon Event Manager
/// (no Accessibility permission required).
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
    
    private static let signature: OSType = 0x4D55544C // 'MUTL'
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?
    private var isStarted = false
    private var registered: [Shortcut] = []
    
    private init() {}
    
    public func start() {
        guard !isStarted else { return reloadIfNeeded() }
        isStarted = true
        
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handler: EventHandlerUPP = { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let err = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            // Let other handlers (the clipboard picker's) see hot keys that aren't ours.
            guard err == noErr, hotKeyID.signature == QuickToolsHotkeys.signature else {
                return OSStatus(eventNotHandledErr)
            }
            do {
                let id = hotKeyID.id
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        QuickToolsHotkeys.shared.handleHotKey(id: id)
                    }
                }
            }
            return noErr
        }
        
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventSpec, nil, &eventHandlerRef)
        
        registerAll()
    }
    
    private func registerAll() {
        hotKeyRefs.forEach { UnregisterEventHotKey($0) }
        hotKeyRefs.removeAll()
        registered = Self.shortcuts.map(\.current)
        for (sc, key) in zip(Self.shortcuts, registered) {
            var ref: EventHotKeyRef?
            let hkID = EventHotKeyID(signature: Self.signature, id: sc.id)
            if RegisterEventHotKey(key.keyCode, key.modifiers, hkID, GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
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
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
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
