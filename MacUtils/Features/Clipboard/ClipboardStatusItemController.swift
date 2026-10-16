import AppKit

/// Menu bar clipboard icon: lists recent copies (click to paste) plus quick controls.
@MainActor
public final class ClipboardStatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let store = ClipboardStore.shared
    private static let menuItemCount = 12
    
    public override init() {
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        if let button = statusItem.button { button.toolTip = "Clipboard history (hold ⌘⇧ and press V)" }
        refreshIcon()
        syncVisibility()
    }
    
    public func syncVisibility() {
        let prefs = AppPreferences.shared
        statusItem.isVisible = prefs.clipboardEnabled && prefs.showClipboardIcon
        refreshIcon()
    }
    
    public func removeFromStatusBar() {
        NSStatusBar.system.removeStatusItem(statusItem)
    }
    
    private func refreshIcon() {
        let paused = AppPreferences.shared.clipboardPaused
        let image = NSImage(systemSymbolName: paused ? "pause.circle" : "doc.on.clipboard", accessibilityDescription: "Clipboard")
        image?.isTemplate = true
        statusItem.button?.image = image
    }
    
    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let prefs = AppPreferences.shared
        
        let header = NSMenuItem(title: prefs.clipboardPaused ? "Clipboard (recording paused)" : "Clipboard", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        
        let items = Array(store.items.prefix(Self.menuItemCount))
        if items.isEmpty {
            let empty = NSMenuItem(title: "Nothing copied yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for (index, entry) in items.enumerated() {
            let title = String(entry.title.prefix(60))
            let item = NSMenuItem(title: title, action: #selector(pasteItem(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            if let image = entry.image {
                let thumb = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
                    image.draw(in: rect); return true
                }
                item.image = thumb
            } else {
                let symbol = NSImage(systemSymbolName: entry.symbolName, accessibilityDescription: nil)
                symbol?.isTemplate = true
                item.image = symbol
            }
            menu.addItem(item)
        }
        
        menu.addItem(.separator())
        let hint = NSMenuItem(title: "Hold ⌘⇧ and press V anywhere for the picker", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())
        
        let pause = NSMenuItem(title: prefs.clipboardPaused ? "Resume Recording" : "Pause Recording", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)
        let clear = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        clear.isEnabled = !store.items.isEmpty
        menu.addItem(clear)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Clipboard Settings...", action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        if let update = MenuActionsHandler.shared.updateItem() { menu.addItem(.separator()); menu.addItem(update) }
        let quit = NSMenuItem(title: "Quit MacUtils", action: #selector(MenuActionsHandler.quitApp), keyEquivalent: "q")
        quit.target = MenuActionsHandler.shared
        menu.addItem(quit)
    }
    
    @objc private func pasteItem(_ sender: NSMenuItem) {
        let items = store.items
        guard sender.tag < items.count else { return }
        // Give the menu time to close and focus to return to the app you were typing in.
        PasteService.paste(items[sender.tag], after: 0.2)
    }
    
    @objc private func togglePause() {
        AppPreferences.shared.clipboardPaused.toggle()
        refreshIcon()
    }
    
    @objc private func clearHistory() { store.clear() }
    
    @objc private func openSettings() {
        PreferencesWindowController.shared.showPreferences(selecting: .clipboard)
    }
}
