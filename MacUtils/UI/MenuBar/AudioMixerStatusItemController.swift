import AppKit

/// Menu bar Audio Mixer icon. Left-click opens the Per-App Volume Mixer popover;
/// right-click (or ⌃-click) opens quick options.
@MainActor
public final class AudioMixerStatusItemController: NSObject, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let popoverVC = AudioMixerPopoverViewController()
    
    public override init() {
        super.init()
        popover.contentSize = NSSize(width: 350, height: 460)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = popoverVC
        popover.delegate = self
    }
    
    public func install() {
        removeFromStatusBar()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let button = item.button {
            let image = NSImage(systemSymbolName: "slider.vertical.3", accessibilityDescription: "Per-App Audio Mixer")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Per-App Audio Mixer"
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        syncVisibility()
    }
    
    public func syncVisibility() {
        statusItem?.isVisible = AppPreferences.shared.showAudioMixer
    }
    
    public func removeFromStatusBar() {
        closePopover()
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
    }
    
    public func closePopover() {
        if popover.isShown { popover.close() }
    }
    
    public func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.close()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
    
    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if wantsMenu {
            let menu = NSMenu()
            let reset = NSMenuItem(title: "Reset All App Volumes to 100%", action: #selector(resetAll), keyEquivalent: "")
            reset.target = self
            menu.addItem(reset)
            menu.addItem(.separator())
            let settings = NSMenuItem(title: "Preferences...", action: #selector(openSettings), keyEquivalent: ",")
            settings.target = self
            menu.addItem(settings)
            if let update = MenuActionsHandler.shared.updateItem() { menu.addItem(.separator()); menu.addItem(update) }
            let quit = NSMenuItem(title: "Quit MacUtils", action: #selector(MenuActionsHandler.quitApp), keyEquivalent: "q")
            quit.target = MenuActionsHandler.shared
            menu.addItem(quit)
            
            statusItem?.menu = menu
            sender.performClick(nil)
            statusItem?.menu = nil
        } else {
            togglePopover()
        }
    }
    
    @objc private func resetAll() {
        PerAppAudioManager.shared.resetAll()
    }
    
    @objc private func openSettings() {
        PreferencesWindowController.shared.showPreferences(selecting: .tools)
    }
}
