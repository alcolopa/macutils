import AppKit
import Carbon.HIToolbox

/// Global clipboard picker (⌘⇧V by default, configurable). Press the shortcut to open the panel, then
/// click an item or use ↑/↓ and Return to paste it, Esc to cancel. As in Flycut, you can also keep the
/// modifiers held, press the key again to move down, and let go to paste.
///
/// The shortcut is a Carbon hot key, so showing the picker needs no special permission. Only the final
/// ⌘V keystroke needs Accessibility access; without it the item is just placed on the clipboard.
@MainActor
public final class ClipboardPicker {
    public static let shared = ClipboardPicker()
    
    private enum HotKey { case open, escape, up, down, enter }
    
    private var openKey: EventHotKeyRef?
    private var modalKeys: [EventHotKeyRef] = []
    private var flagsTimer: Timer?
    private var registeredShortcut: Shortcut?
    private var wasDown = false
    private var cycled = false
    static let defaultShortcut = Shortcut(keyCode: kVK_ANSI_V, modifiers: cmdKey | shiftKey, character: "v")
    static var shortcut: Shortcut { AppPreferences.shared.shortcut("clipboard", default: defaultShortcut) }
    
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
        let wanted = Self.shortcut
        guard registeredShortcut != wanted else { return }
        if let openKey { GlobalHotKeys.shared.unregister(openKey) }
        registeredShortcut = wanted
        openKey = register(wanted, id: .open)
        isShortcutActive = openKey != nil
    }
    
    public func stop() {
        if isShowing { hide() }
        if let openKey { GlobalHotKeys.shared.unregister(openKey) }
        openKey = nil
        registeredShortcut = nil
        isShortcutActive = false
        ClipboardStore.shared.stop()
    }
    
    private func register(_ shortcut: Shortcut, id: HotKey) -> EventHotKeyRef? {
        register(keyCode: Int(shortcut.keyCode), modifiers: shortcut.modifiers, id: id)
    }
    
    private func register(keyCode: Int, modifiers: UInt32, id: HotKey) -> EventHotKeyRef? {
        GlobalHotKeys.shared.register(keyCode: UInt32(keyCode), modifiers: modifiers) { [weak self] in
            self?.hotKeyPressed(id)
        }
    }
    
    private func hotKeyPressed(_ key: HotKey) {
        switch key {
        case .open: isShowing ? step(1) : show()
        case .escape: hide()
        case .up: step(-1)
        case .down: step(1)
        case .enter: commit()
        }
    }
    
    private func show() {
        snapshot = ClipboardStore.shared.items
        selected = 0
        isShowing = true
        let open = Self.shortcut
        // Only exist while the picker is up: bare keys for the click-and-type flow, with the
        // shortcut's modifiers for the hold-and-cycle flow.
        modalKeys = [open.modifiers, 0].flatMap { mods in
            [(kVK_Escape, HotKey.escape), (kVK_UpArrow, .up), (kVK_DownArrow, .down), (kVK_Return, .enter)]
                .compactMap { register(keyCode: $0.0, modifiers: mods, id: $0.1) }
        }
        panel.present(items: snapshot, selected: selected)
        wasDown = true
        cycled = false
        flagsTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isShowing else { return }
                let down = NSEvent.modifierFlags.isSuperset(of: open.flags)
                if down { self.wasDown = true }
                else if self.wasDown {
                    // Released: paste if the user was cycling with the shortcut held, else stay open.
                    self.wasDown = false
                    if self.cycled { self.commit() }
                }
            }
        }
    }
    
    private func step(_ delta: Int) {
        cycled = true
        move(by: delta)
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
        modalKeys.forEach { GlobalHotKeys.shared.unregister($0) }
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
