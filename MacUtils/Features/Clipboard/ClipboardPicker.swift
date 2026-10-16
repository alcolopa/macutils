import AppKit
import Carbon.HIToolbox

/// Global ⌘⇧V picker. Holding ⌘⇧ keeps the panel open, each press of V moves to the next item, and
/// letting go of ⌘ or ⇧ pastes the highlighted one into the frontmost app.
///
/// The shortcut is a Carbon hot key, so showing the picker needs no special permission. Only the final
/// ⌘V keystroke needs Accessibility access; without it the item is just placed on the clipboard.
@MainActor
public final class ClipboardPicker {
    public static let shared = ClipboardPicker()
    
    private enum HotKey: UInt32 { case open = 1, escape, up, down }
    
    private var handlerRef: EventHandlerRef?
    private var openKey: EventHotKeyRef?
    private var modalKeys: [EventHotKeyRef] = []
    private var flagsTimer: Timer?
    
    private let panel = ClipboardPanel()
    private var snapshot: [ClipboardItem] = []
    private var selected = 0
    private var isShowing = false
    
    /// False when another app already owns ⌘⇧V.
    public private(set) var isShortcutActive = false
    
    private init() {
        panel.onRowClicked = { [weak self] index in
            self?.selected = index
            self?.commit()
        }
    }
    
    public func start() {
        ClipboardStore.shared.start()
        installHandlerIfNeeded()
        guard openKey == nil else { return }
        openKey = register(keyCode: kVK_ANSI_V, id: .open)
        isShortcutActive = openKey != nil
    }
    
    public func stop() {
        if isShowing { hide() }
        if let openKey { UnregisterEventHotKey(openKey) }
        openKey = nil
        isShortcutActive = false
        ClipboardStore.shared.stop()
    }
    
    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), clipboardHotKeyHandler, 1, &spec,
                            Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }
    
    private func register(keyCode: Int, id: HotKey) -> EventHotKeyRef? {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4D555449), id: id.rawValue) // 'MUTI'
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(cmdKey | shiftKey), hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        return status == noErr ? ref : nil
    }
    
    fileprivate func hotKeyPressed(_ rawID: UInt32) {
        guard let key = HotKey(rawValue: rawID) else { return }
        switch key {
        case .open: isShowing ? move(by: 1) : show()
        case .escape: hide()
        case .up: move(by: -1)
        case .down: move(by: 1)
        }
    }
    
    private func show() {
        snapshot = ClipboardStore.shared.items
        selected = 0
        isShowing = true
        // While the picker is up ⌘⇧ is held, so these only exist for the duration.
        modalKeys = [(kVK_Escape, HotKey.escape), (kVK_UpArrow, .up), (kVK_DownArrow, .down)]
            .compactMap { register(keyCode: $0.0, id: $0.1) }
        panel.present(items: snapshot, selected: selected)
        flagsTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isShowing else { return }
                let flags = NSEvent.modifierFlags
                if !(flags.contains(.command) && flags.contains(.shift)) { self.commit() }
            }
        }
    }
    
    private func move(by delta: Int) {
        guard !snapshot.isEmpty else { return }
        selected = (selected + delta + snapshot.count) % snapshot.count
        panel.update(selected: selected)
    }
    
    private func hide() {
        isShowing = false
        flagsTimer?.invalidate()
        flagsTimer = nil
        modalKeys.forEach { UnregisterEventHotKey($0) }
        modalKeys.removeAll()
        panel.orderOut(nil)
    }
    
    private func commit() {
        guard isShowing else { return }
        let item = selected < snapshot.count ? snapshot[selected] : nil
        hide()
        guard let item else { return }
        if !PasteService.paste(item) {
            panel.showMessage("Copied. Press ⌘V to paste.", detail: "Allow MacUtils in Privacy & Security → Accessibility to paste automatically.")
        }
    }
}

private func clipboardHotKeyHandler(_ next: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let userData, let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                   nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    guard status == noErr else { return status }
    let picker = Unmanaged<ClipboardPicker>.fromOpaque(userData).takeUnretainedValue()
    // Hot key events are delivered on the main thread.
    MainActor.assumeIsolated { picker.hotKeyPressed(hotKeyID.id) }
    return noErr
}
