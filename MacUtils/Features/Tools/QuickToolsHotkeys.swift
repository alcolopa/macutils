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
        public let display: String
        public let keyCode: UInt32
        public let modifiers: UInt32
    }
    
    public static let shortcuts: [ShortcutInfo] = [
        ShortcutInfo(id: 1, title: "Extract Text from Screen (OCR)", display: "⌘⇧2", keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(cmdKey | shiftKey)),
        ShortcutInfo(id: 2, title: "Pick Screen Color", display: "⌘⇧X", keyCode: UInt32(kVK_ANSI_X), modifiers: UInt32(cmdKey | shiftKey)),
        ShortcutInfo(id: 3, title: "Quick Scratchpad", display: "⌘⇧N", keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(cmdKey | shiftKey)),
        ShortcutInfo(id: 4, title: "Toggle Microphone Mute", display: "⌥⇧M", keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(optionKey | shiftKey)),
        ShortcutInfo(id: 5, title: "Toggle Clean Desktop", display: "⌘⇧D", keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(cmdKey | shiftKey))
    ]
    
    private static let signature: OSType = 0x4D55544C // 'MUTL'
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?
    private var isStarted = false
    
    private init() {}
    
    public func start() {
        guard !isStarted else { return }
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
            if err == noErr && hotKeyID.signature == QuickToolsHotkeys.signature {
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
        
        for sc in Self.shortcuts {
            var ref: EventHotKeyRef?
            let hkID = EventHotKeyID(signature: Self.signature, id: sc.id)
            if RegisterEventHotKey(sc.keyCode, sc.modifiers, hkID, GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
                hotKeyRefs.append(ref)
            }
        }
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
