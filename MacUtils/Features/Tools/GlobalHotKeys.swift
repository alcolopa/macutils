import Carbon.HIToolbox

/// The app's single Carbon hot key handler. Every feature registers through here, so no handler can
/// swallow another's events. Carbon needs no Accessibility permission.
@MainActor
final class GlobalHotKeys {
    static let shared = GlobalHotKeys()
    
    private var actions: [UInt32: () -> Void] = [:]
    private var ids: [EventHotKeyRef: UInt32] = [:]
    private var nextID: UInt32 = 1
    private var handlerRef: EventHandlerRef?
    
    private init() {}
    
    /// Returns nil if the combination is taken (or invalid). Keep the ref to `unregister` it later.
    func register(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) -> EventHotKeyRef? {
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let id = nextID
        guard RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: 0x4D555458, id: id), // 'MUTX'
                                  GetApplicationEventTarget(), 0, &ref) == noErr, let ref else { return nil }
        nextID += 1
        actions[id] = action
        ids[ref] = id
        return ref
    }
    
    func unregister(_ ref: EventHotKeyRef) {
        UnregisterEventHotKey(ref)
        if let id = ids.removeValue(forKey: ref) { actions[id] = nil }
    }
    
    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            guard let event, GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                               nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID) == noErr
            else { return OSStatus(eventNotHandledErr) }
            // Hot key events are delivered on the main thread.
            MainActor.assumeIsolated { GlobalHotKeys.shared.actions[hotKeyID.id]?() }
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }
}
