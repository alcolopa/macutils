import AppKit
import Carbon.HIToolbox
import IOKit.pwr_mgt

/// CleaningModeManager locks all keyboard, trackpad, and mouse input behind a fullscreen
/// blackout shield so users can safely wipe down their keyboard, trackpad, and screen
/// without accidental typing, clicks, or gestures affecting open applications.
///
/// To prevent accidental dismissal while wiping the keyboard, exiting requires holding
/// the Escape key (or holding the on-screen unlock button) for 3 continuous seconds.
@MainActor
public final class CleaningModeManager: NSObject {
    public static let shared = CleaningModeManager()
    
    public static let didEnterCleaningMode = Notification.Name("MacUtilsDidEnterCleaningMode")
    public static let didExitCleaningMode = Notification.Name("MacUtilsDidExitCleaningMode")
    
    public private(set) var isActive: Bool = false
    public private(set) var blockedEventCount: Int = 0
    
    private var windows: [CleaningOverlayWindow] = []
    private var savedPresentationOptions: NSApplication.PresentationOptions = []
    private var sleepAssertionID: IOPMAssertionID = 0
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    // Hold-to-exit state
    private var isHoldingExitKey: Bool = false
    private var holdStartTime: Date?
    private var holdTimer: Timer?
    private let holdDurationRequired: TimeInterval = 2.5
    
    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleScreenChange()
            }
        }
    }
    
    // MARK: - Public API
    
    public func start() {
        guard !isActive else { return }
        isActive = true
        blockedEventCount = 0
        isHoldingExitKey = false
        holdStartTime = nil
        
        // Prevent system and display sleep during cleaning
        preventSleep()
        
        // Hide dock, menu bar, and disable switching apps (Cmd+Tab, etc.)
        savedPresentationOptions = NSApp.presentationOptions
        NSApp.presentationOptions = [
            .hideDock,
            .hideMenuBar,
            .disableProcessSwitching,
            .disableForceQuit,
            .disableSessionTermination,
            .disableAppleMenu
        ]
        
        // Create full screen overlay windows on all connected displays
        createOverlayWindows()
        
        // Install CGEventTap if accessibility permissions permit (extra layer of protection)
        installEventTap()
        
        // Hide mouse cursor initially for clean screen wipe
        NSCursor.hide()
        
        NotificationCenter.default.post(name: Self.didEnterCleaningMode, object: nil)
    }
    
    public func stop() {
        guard isActive else { return }
        isActive = false
        
        // Cancel hold timers
        resetHoldProgress()
        
        // Remove event tap
        uninstallEventTap()
        
        // Close overlay windows
        for win in windows {
            win.orderOut(nil)
        }
        windows.removeAll()
        
        // Restore cursor and presentation options
        NSCursor.unhide()
        NSApp.presentationOptions = savedPresentationOptions
        
        // Restore power assertion
        allowSleep()
        
        // Play gentle audio feedback indicating successful unlock
        NSSound(named: "Glass")?.play()
        
        NotificationCenter.default.post(name: Self.didExitCleaningMode, object: nil)
    }
    
    public func toggle() {
        if isActive {
            stop()
        } else {
            start()
        }
    }
    
    // MARK: - Event Interception & Tracking
    
    public func recordBlockedEvent() {
        guard isActive else { return }
        blockedEventCount += 1
        for win in windows {
            win.overlayView.updateBlockedCount(blockedEventCount)
        }
    }
    
    public func handleKeyDown(keyCode: UInt16) {
        guard isActive else { return }
        recordBlockedEvent()
        
        // Escape key code is 53
        if keyCode == 53 {
            if !isHoldingExitKey {
                beginHoldExit()
            }
        }
    }
    
    public func handleKeyUp(keyCode: UInt16) {
        guard isActive else { return }
        if keyCode == 53 {
            endHoldExit()
        }
    }
    
    public func beginHoldExit() {
        guard isActive, !isHoldingExitKey else { return }
        isHoldingExitKey = true
        holdStartTime = Date()
        
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tickHoldProgress()
            }
        }
    }
    
    public func endHoldExit() {
        guard isHoldingExitKey else { return }
        isHoldingExitKey = false
        holdStartTime = nil
        holdTimer?.invalidate()
        holdTimer = nil
        resetHoldProgress()
    }
    
    private func tickHoldProgress() {
        guard isActive, isHoldingExitKey, let start = holdStartTime else {
            resetHoldProgress()
            return
        }
        
        let elapsed = Date().timeIntervalSince(start)
        let progress = min(elapsed / holdDurationRequired, 1.0)
        
        for win in windows {
            win.overlayView.updateHoldProgress(CGFloat(progress))
        }
        
        if progress >= 1.0 {
            holdTimer?.invalidate()
            holdTimer = nil
            stop()
        }
    }
    
    private func resetHoldProgress() {
        for win in windows {
            win.overlayView.updateHoldProgress(0.0)
        }
    }
    
    // MARK: - Windows & Displays
    
    private func createOverlayWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        
        for screen in NSScreen.screens {
            let win = CleaningOverlayWindow(screen: screen)
            windows.append(win)
            win.makeKeyAndOrderFront(nil)
        }
        
        // Ensure the main display's window is key
        if let first = windows.first {
            first.makeKey()
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func handleScreenChange() {
        guard isActive else { return }
        createOverlayWindows()
    }
    
    // MARK: - Event Tap
    
    private func installEventTap() {
        guard AXIsProcessTrusted() else { return }
        
        let mask = (1 << CGEventType.keyDown.rawValue) |
                   (1 << CGEventType.keyUp.rawValue) |
                   (1 << CGEventType.flagsChanged.rawValue) |
                   (1 << CGEventType.leftMouseDown.rawValue) |
                   (1 << CGEventType.leftMouseUp.rawValue) |
                   (1 << CGEventType.rightMouseDown.rawValue) |
                   (1 << CGEventType.rightMouseUp.rawValue) |
                   (1 << CGEventType.otherMouseDown.rawValue) |
                   (1 << CGEventType.otherMouseUp.rawValue) |
                   (1 << CGEventType.scrollWheel.rawValue)
        
        let callback: CGEventTapCallBack = { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
            guard let refcon = refcon else { return Unmanaged.passRetained(event) }
            let manager = Unmanaged<CleaningModeManager>.fromOpaque(refcon).takeUnretainedValue()
            
            // Check if key is Escape
            if type == .keyDown || type == .keyUp {
                let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                DispatchQueue.main.async {
                    if type == .keyDown {
                        manager.handleKeyDown(keyCode: keyCode)
                    } else {
                        manager.handleKeyUp(keyCode: keyCode)
                    }
                }
            } else {
                DispatchQueue.main.async {
                    manager.recordBlockedEvent()
                }
            }
            
            // Suppress the event from reaching system or other apps
            return nil
        }
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }
        
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
    
    private func uninstallEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let src = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            }
            CFMachPortInvalidate(tap)
        }
        eventTap = nil
        runLoopSource = nil
    }
    
    // MARK: - Power Assertion
    
    private func preventSleep() {
        guard sleepAssertionID == 0 else { return }
        let reason = "Cleaning Mac Display and Keyboard" as CFString
        IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &sleepAssertionID
        )
    }
    
    private func allowSleep() {
        guard sleepAssertionID != 0 else { return }
        IOPMAssertionRelease(sleepAssertionID)
        sleepAssertionID = 0
    }
}

// MARK: - Cleaning Overlay Window

public final class CleaningOverlayWindow: NSWindow {
    public let overlayView: CleaningOverlayView
    
    public init(screen: NSScreen) {
        let frame = screen.frame
        self.overlayView = CleaningOverlayView(frame: NSRect(origin: .zero, size: frame.size))
        
        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        
        self.contentView = overlayView
        self.isOpaque = true
        self.backgroundColor = .black
        self.level = NSWindow.Level(Int(CGWindowLevelForKey(.maximumWindow)))
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.hidesOnDeactivate = false
    }
    
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }
    
    public override func keyDown(with event: NSEvent) {
        CleaningModeManager.shared.handleKeyDown(keyCode: event.keyCode)
    }
    
    public override func keyUp(with event: NSEvent) {
        CleaningModeManager.shared.handleKeyUp(keyCode: event.keyCode)
    }
    
    public override func flagsChanged(with event: NSEvent) {
        CleaningModeManager.shared.recordBlockedEvent()
    }
    
    public override func mouseDown(with event: NSEvent) {
        CleaningModeManager.shared.recordBlockedEvent()
    }
    
    public override func mouseUp(with event: NSEvent) {
        CleaningModeManager.shared.recordBlockedEvent()
    }
    
    public override func mouseDragged(with event: NSEvent) {
        CleaningModeManager.shared.recordBlockedEvent()
    }
    
    public override func rightMouseDown(with event: NSEvent) {
        CleaningModeManager.shared.recordBlockedEvent()
    }
    
    public override func rightMouseUp(with event: NSEvent) {
        CleaningModeManager.shared.recordBlockedEvent()
    }
    
    public override func otherMouseDown(with event: NSEvent) {
        CleaningModeManager.shared.recordBlockedEvent()
    }
    
    public override func scrollWheel(with event: NSEvent) {
        CleaningModeManager.shared.recordBlockedEvent()
    }
}

// MARK: - Cleaning Overlay View

public final class CleaningOverlayView: NSView {
    private let hudBox = NSVisualEffectView()
    private let titleLabel = NSTextField(labelWithString: "Cleaning Mode Active")
    private let subtitleLabel = NSTextField(labelWithString: "Keyboard, trackpad, and screen inputs are locked so you can safely clean your Mac.")
    private let blockedBadge = NSTextField(labelWithString: "0 inputs blocked")
    private let progressRing = UnlockProgressRingView()
    private let instructionLabel = NSTextField(labelWithString: "Hold [ Esc ] for 3 seconds to exit")
    private let unlockButton = NSButton()
    private let blackoutButton = NSButton()
    
    private var isBlackoutMode: Bool = false
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1.0).cgColor
        setupUI()
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        // Floating Center Card
        hudBox.translatesAutoresizingMaskIntoConstraints = false
        hudBox.material = .hudWindow
        hudBox.blendingMode = .withinWindow
        hudBox.state = .active
        hudBox.wantsLayer = true
        hudBox.layer?.cornerRadius = 24
        hudBox.layer?.masksToBounds = true
        hudBox.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        hudBox.layer?.borderWidth = 1.0
        addSubview(hudBox)
        
        let iconView = NSImageView(image: NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Cleaning Mode") ?? NSImage())
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentTintColor = NSColor.systemTeal
        iconView.symbolConfiguration = .init(pointSize: 42, weight: .light)
        
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.alignment = .center
        
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.65)
        subtitleLabel.alignment = .center
        subtitleLabel.maximumNumberOfLines = 2
        
        blockedBadge.translatesAutoresizingMaskIntoConstraints = false
        blockedBadge.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        blockedBadge.textColor = NSColor.systemTeal.blended(withFraction: 0.2, of: .white)
        blockedBadge.alignment = .center
        
        progressRing.translatesAutoresizingMaskIntoConstraints = false
        
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        instructionLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        instructionLabel.textColor = NSColor.white.withAlphaComponent(0.85)
        instructionLabel.alignment = .center
        
        // Hold-to-Unlock mouse button
        unlockButton.translatesAutoresizingMaskIntoConstraints = false
        unlockButton.title = "Click & Hold to Exit"
        unlockButton.bezelStyle = .rounded
        unlockButton.controlSize = .large
        unlockButton.isBordered = false
        unlockButton.wantsLayer = true
        unlockButton.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
        unlockButton.layer?.cornerRadius = 10
        unlockButton.target = self
        unlockButton.action = #selector(unlockButtonClicked)
        
        // Add gesture recognizer for press-and-hold mouse unlock
        let pressRecognizer = NSPressGestureRecognizer(target: self, action: #selector(handlePressGesture(_:)))
        pressRecognizer.minimumPressDuration = 0.05
        unlockButton.addGestureRecognizer(pressRecognizer)
        
        // Blackout Screen button (allows pure black glass inspection)
        blackoutButton.translatesAutoresizingMaskIntoConstraints = false
        blackoutButton.title = "Screen Dust Check (Pure Black)"
        blackoutButton.bezelStyle = .inline
        blackoutButton.isBordered = false
        blackoutButton.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        blackoutButton.contentTintColor = NSColor.white.withAlphaComponent(0.4)
        blackoutButton.target = self
        blackoutButton.action = #selector(toggleBlackout)
        
        let stack = NSStackView(views: [
            iconView,
            titleLabel,
            subtitleLabel,
            blockedBadge,
            progressRing,
            instructionLabel,
            unlockButton,
            blackoutButton
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.setCustomSpacing(6, after: titleLabel)
        stack.setCustomSpacing(12, after: subtitleLabel)
        stack.setCustomSpacing(18, after: blockedBadge)
        stack.setCustomSpacing(8, after: progressRing)
        stack.setCustomSpacing(16, after: instructionLabel)
        stack.setCustomSpacing(10, after: unlockButton)
        
        hudBox.addSubview(stack)
        
        NSLayoutConstraint.activate([
            hudBox.centerXAnchor.constraint(equalTo: centerXAnchor),
            hudBox.centerYAnchor.constraint(equalTo: centerYAnchor),
            hudBox.widthAnchor.constraint(equalToConstant: 440),
            
            stack.topAnchor.constraint(equalTo: hudBox.topAnchor, constant: 28),
            stack.leadingAnchor.constraint(equalTo: hudBox.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: hudBox.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: hudBox.bottomAnchor, constant: -24),
            
            progressRing.widthAnchor.constraint(equalToConstant: 76),
            progressRing.heightAnchor.constraint(equalToConstant: 76),
            
            unlockButton.widthAnchor.constraint(equalToConstant: 200),
            unlockButton.heightAnchor.constraint(equalToConstant: 34)
        ])
    }
    
    public func updateBlockedCount(_ count: Int) {
        blockedBadge.stringValue = "\(count) \(count == 1 ? "input" : "inputs") blocked"
        // If in blackout mode, touching/clicking temporarily reveals a subtle hint
        if isBlackoutMode {
            // Flash a gentle glow
            NSSound.beep()
        }
    }
    
    public func updateHoldProgress(_ progress: CGFloat) {
        progressRing.progress = progress
        if progress > 0 {
            let pct = Int(round(progress * 100))
            instructionLabel.stringValue = "Releasing in \(max(0, Int(ceil((1.0 - progress) * 2.5))))s (\(pct)%)"
        } else {
            instructionLabel.stringValue = "Hold [ Esc ] for 3 seconds to exit"
        }
    }
    
    @objc private func toggleBlackout() {
        isBlackoutMode.toggle()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            hudBox.animator().alphaValue = isBlackoutMode ? 0.0 : 1.0
            layer?.backgroundColor = isBlackoutMode ? NSColor.black.cgColor : NSColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1.0).cgColor
        }
    }
    
    @objc private func unlockButtonClicked() {
        // Normal click doesn't exit; informs user to hold
        instructionLabel.stringValue = "Please hold the button for 3 seconds"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            if CleaningModeManager.shared.isActive {
                self?.instructionLabel.stringValue = "Hold [ Esc ] for 3 seconds to exit"
            }
        }
    }
    
    @objc private func handlePressGesture(_ recognizer: NSPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            CleaningModeManager.shared.beginHoldExit()
        case .ended, .cancelled, .failed:
            CleaningModeManager.shared.endHoldExit()
        default:
            break
        }
    }
    
    public override func mouseDown(with event: NSEvent) {
        // If blackout mode is active, clicking anywhere reveals HUD
        if isBlackoutMode {
            toggleBlackout()
            return
        }
        super.mouseDown(with: event)
    }
}

// MARK: - Unlock Progress Ring View

public final class UnlockProgressRingView: NSView {
    public var progress: CGFloat = 0.0 {
        didSet {
            needsDisplay = true
        }
    }
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let lineWidth: CGFloat = 4.5
        let radius = (min(bounds.width, bounds.height) - lineWidth) / 2.0
        
        // Track ring
        ctx.saveGState()
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.15).cgColor)
        ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.strokePath()
        
        // Progress arc
        if progress > 0.001 {
            let startAngle: CGFloat = .pi / 2.0
            let endAngle = startAngle - (progress * .pi * 2.0)
            
            let color = NSColor.systemTeal.blended(withFraction: Double(progress), of: .systemGreen) ?? .systemTeal
            ctx.setStrokeColor(color.cgColor)
            ctx.beginPath()
            ctx.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
            ctx.strokePath()
        }
        ctx.restoreGState()
        
        // Center text: "ESC"
        let text = "ESC"
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
        let textColor = progress > 0.0 ? NSColor.systemGreen : NSColor.white.withAlphaComponent(0.9)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let s = str.size()
        str.draw(at: CGPoint(x: bounds.midX - s.width / 2.0, y: bounds.midY - s.height / 2.0))
    }
}
