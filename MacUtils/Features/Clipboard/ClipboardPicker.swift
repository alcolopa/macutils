import AppKit
import ApplicationServices

/// Global ⌘⇧V picker. Holding ⌘⇧ keeps the panel open, each press of V moves to the next item, and
/// letting go of ⌘ or ⇧ pastes the highlighted one into the frontmost app.
///
/// Uses a CGEventTap so the keystroke can be swallowed; that needs the Accessibility permission, which
/// is also what lets us post the synthetic ⌘V.
@MainActor
public final class ClipboardPicker {
    public static let shared = ClipboardPicker()
    
    private static let keyV: Int64 = 9
    private static let keyEscape: Int64 = 53
    private static let keyDown: Int64 = 125
    private static let keyUp: Int64 = 126
    
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var retryTimer: Timer?
    private var flagsTimer: Timer?
    private var didPrompt = false
    
    private let panel = ClipboardPanel()
    private var snapshot: [String] = []
    private var selected = 0
    private var isShowing = false
    private var swallowedVDown = false
    
    private init() {
        panel.onRowClicked = { [weak self] index in
            self?.selected = index
            self?.commit()
        }
    }
    
    public func start() {
        ClipboardStore.shared.start()
        guard tap == nil, retryTimer == nil else { return }
        if !installTap() {
            if !didPrompt {
                didPrompt = true
                AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            }
            // Keep trying so the shortcut starts working as soon as the permission is granted.
            retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if self.installTap() { self.retryTimer?.invalidate(); self.retryTimer = nil }
                }
            }
        }
    }
    
    public func stop() {
        retryTimer?.invalidate()
        retryTimer = nil
        if isShowing { cancel() }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        tap = nil
        tapSource = nil
        ClipboardStore.shared.stop()
    }
    
    public var hasAccessibilityAccess: Bool { AXIsProcessTrusted() }
    
    private func installTap() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(mask), callback: clipboardTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        tapSource = source
        return true
    }
    
    /// Returns true when the event must be swallowed.
    fileprivate func handle(type: CGEventType, keyCode: Int64, flags: CGEventFlags, isRepeat: Bool) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
            
        case .flagsChanged:
            if isShowing && !Self.comboHeld(flags) { commit() }
            return false
            
        case .keyDown:
            if isShowing {
                switch keyCode {
                case Self.keyV:
                    swallowedVDown = true
                    if !isRepeat { move(by: 1) }
                    return true
                case Self.keyDown: move(by: 1); return true
                case Self.keyUp: move(by: -1); return true
                case Self.keyEscape: cancel(); return true
                default: return false
                }
            }
            let relevant = flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])
            if keyCode == Self.keyV, relevant == [.maskCommand, .maskShift] {
                swallowedVDown = true
                if !isRepeat { show() }
                return true
            }
            return false
            
        case .keyUp:
            if keyCode == Self.keyV, swallowedVDown {
                swallowedVDown = false
                return true
            }
            return false
            
        default:
            return false
        }
    }
    
    private static func comboHeld(_ flags: CGEventFlags) -> Bool {
        flags.contains(.maskCommand) && flags.contains(.maskShift)
    }
    
    private func show() {
        snapshot = ClipboardStore.shared.items
        selected = 0
        isShowing = true
        panel.present(items: snapshot, selected: selected)
        // Safety net in case a modifier release is ever missed by the tap.
        flagsTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isShowing else { return }
                if !Self.comboHeld(CGEventSource.flagsState(.combinedSessionState)) { self.commit() }
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
        panel.orderOut(nil)
    }
    
    private func cancel() { hide() }
    
    private func commit() {
        guard isShowing else { return }
        let text = selected < snapshot.count ? snapshot[selected] : nil
        hide()
        guard let text else { return }
        ClipboardStore.shared.writeToPasteboard(text)
        // Let the panel disappear and modifiers settle before sending ⌘V to the frontmost app.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { Self.postPaste() }
    }
    
    private static func postPaste() {
        let source = CGEventSource(stateID: .hidSystemState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyV), keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}

private func clipboardTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags
    let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    let picker = Unmanaged<ClipboardPicker>.fromOpaque(refcon).takeUnretainedValue()
    // The tap is attached to the main run loop, so this always runs on the main thread.
    let swallow = MainActor.assumeIsolated { picker.handle(type: type, keyCode: keyCode, flags: flags, isRepeat: isRepeat) }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
