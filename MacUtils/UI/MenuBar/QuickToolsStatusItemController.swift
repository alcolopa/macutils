import AppKit

@MainActor
public final class QuickToolsStatusItemController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let audioManager = AudioHardwareManager.shared
    private let desktopManager = CleanDesktopManager.shared
    private let portReader = DarwinPortReader.shared
    private let displayManager = DisplayControlManager.shared
    private var privacyTimer: Timer?
    
    public override init() {
        super.init()
        NotificationCenter.default.addObserver(forName: AudioHardwareManager.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshIcon() }
        }
        NotificationCenter.default.addObserver(forName: CleanDesktopManager.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshIcon() }
        }
    }
    
    public func install() {
        removeFromStatusBar()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        item.button?.toolTip = "Quick Tools & Utilities"
        refreshIcon()
        syncVisibility()
        startPrivacyPolling()
    }
    
    public func syncVisibility() {
        statusItem?.isVisible = AppPreferences.shared.showTools
    }
    
    public func removeFromStatusBar() {
        privacyTimer?.invalidate()
        privacyTimer = nil
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
    }
    
    private func startPrivacyPolling() {
        privacyTimer?.invalidate()
        privacyTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshIcon() }
        }
    }
    
    private func refreshIcon() {
        let isMicMuted = audioManager.isInputMuted()
        let camActive = audioManager.isAnyCameraInUse()
        let micActive = audioManager.isAnyMicrophoneInUse()
        
        if isMicMuted {
            let image = NSImage(systemSymbolName: "mic.slash.fill", accessibilityDescription: "Microphone Muted")
            image?.isTemplate = false
            let config = NSImage.SymbolConfiguration(paletteColors: [.systemOrange])
            statusItem?.button?.image = image?.withSymbolConfiguration(config)
            statusItem?.button?.toolTip = "Quick Tools · Microphone is Muted"
        } else if camActive {
            let image = NSImage(systemSymbolName: "video.fill", accessibilityDescription: "Camera Active")
            image?.isTemplate = false
            let config = NSImage.SymbolConfiguration(paletteColors: [.systemGreen])
            statusItem?.button?.image = image?.withSymbolConfiguration(config)
            statusItem?.button?.toolTip = "Quick Tools · Camera is in use"
        } else if micActive {
            let image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Microphone Active")
            image?.isTemplate = false
            let config = NSImage.SymbolConfiguration(paletteColors: [.systemOrange])
            statusItem?.button?.image = image?.withSymbolConfiguration(config)
            statusItem?.button?.toolTip = "Quick Tools · Microphone is in use"
        } else {
            let image = NSImage(systemSymbolName: "wrench.and.screwdriver", accessibilityDescription: "Quick Tools")
            image?.isTemplate = true
            statusItem?.button?.image = image
            statusItem?.button?.toolTip = "Quick Tools & Utilities"
        }
    }
    
    // MARK: - NSMenuDelegate
    
    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let prefs = AppPreferences.shared
        
        let header = NSMenuItem(title: "MacUtils Quick Tools", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        
        // Live Privacy Status
        let camActive = audioManager.isAnyCameraInUse()
        let micActive = audioManager.isAnyMicrophoneInUse()
        if camActive || micActive {
            var parts: [String] = []
            if camActive { parts.append("Camera active") }
            if micActive { parts.append("Mic active") }
            let privacyItem = NSMenuItem(title: "Privacy: " + parts.joined(separator: " · "), action: nil, keyEquivalent: "")
            privacyItem.isEnabled = false
            let sym = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 8, weight: .regular)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [camActive ? .systemGreen : .systemOrange])))
            privacyItem.image = sym
            menu.addItem(privacyItem)
        }
        
        menu.addItem(.separator())
        
        // 1. Microphone Mute
        let isMuted = audioManager.isInputMuted()
        let micTitle = isMuted ? "Unmute Microphone (Muted)" : "Mute Microphone"
        let micItem = NSMenuItem(title: micTitle, action: #selector(toggleMicMute), keyEquivalent: prefs.toolsHotkeysEnabled ? QuickToolsHotkeys.current(id: 4).keyEquivalent : "")
        if prefs.toolsHotkeysEnabled { micItem.keyEquivalentModifierMask = QuickToolsHotkeys.current(id: 4).flags }
        micItem.target = self
        micItem.image = NSImage(systemSymbolName: isMuted ? "mic.slash" : "mic", accessibilityDescription: nil)
        menu.addItem(micItem)
        
        // 2. Clean Desktop Toggle
        let iconsHidden = desktopManager.areIconsHidden
        let dtTitle = iconsHidden ? "Show Desktop Icons" : "Hide Desktop Icons (Clean Desktop)"
        let dtItem = NSMenuItem(title: dtTitle, action: #selector(toggleCleanDesktop), keyEquivalent: prefs.toolsHotkeysEnabled ? QuickToolsHotkeys.current(id: 5).keyEquivalent : "")
        if prefs.toolsHotkeysEnabled { dtItem.keyEquivalentModifierMask = QuickToolsHotkeys.current(id: 5).flags }
        dtItem.target = self
        dtItem.image = NSImage(systemSymbolName: iconsHidden ? "eye" : "eye.slash", accessibilityDescription: nil)
        menu.addItem(dtItem)
        
        menu.addItem(.separator())
        
        // 3. Quick Scratchpad
        let noteItem = NSMenuItem(title: "Quick Scratchpad...", action: #selector(openScratchpad), keyEquivalent: prefs.toolsHotkeysEnabled ? QuickToolsHotkeys.current(id: 3).keyEquivalent : "")
        if prefs.toolsHotkeysEnabled { noteItem.keyEquivalentModifierMask = QuickToolsHotkeys.current(id: 3).flags }
        noteItem.target = self
        noteItem.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: nil)
        menu.addItem(noteItem)
        
        // 4. Screen OCR Text Grabber
        let ocrItem = NSMenuItem(title: "Extract Text from Screen (OCR)...", action: #selector(extractTextOCR), keyEquivalent: prefs.toolsHotkeysEnabled ? QuickToolsHotkeys.current(id: 1).keyEquivalent : "")
        if prefs.toolsHotkeysEnabled { ocrItem.keyEquivalentModifierMask = QuickToolsHotkeys.current(id: 1).flags }
        ocrItem.target = self
        ocrItem.image = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: nil)
        menu.addItem(ocrItem)
        
        // 5. Screen Color Picker
        let colorTitle = "Pick Screen Color (\(prefs.colorPickerFormat.rawValue))..."
        let colorItem = NSMenuItem(title: colorTitle, action: #selector(pickColor), keyEquivalent: prefs.toolsHotkeysEnabled ? QuickToolsHotkeys.current(id: 2).keyEquivalent : "")
        if prefs.toolsHotkeysEnabled { colorItem.keyEquivalentModifierMask = QuickToolsHotkeys.current(id: 2).flags }
        colorItem.target = self
        colorItem.image = NSImage(systemSymbolName: "eyedropper.halffull", accessibilityDescription: nil)
        menu.addItem(colorItem)
        
        menu.addItem(.separator())
        
        // 6. Displays Brightness & Volume (DDC/CI)
        let displays = displayManager.connectedDisplays()
        let displaysMenu = NSMenu()
        if displays.isEmpty {
            let empty = NSMenuItem(title: "No displays detected", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            displaysMenu.addItem(empty)
        } else {
            var extIdx = 0
            for (idx, disp) in displays.enumerated() {
                if idx > 0 { displaysMenu.addItem(.separator()) }
                let label = NSMenuItem(title: disp.name + (disp.isBuiltIn ? " (Built-in)" : " (External)"), action: nil, keyEquivalent: "")
                label.isEnabled = false
                displaysMenu.addItem(label)
                
                let currentExtIdx = extIdx
                if !disp.isBuiltIn { extIdx += 1 }
                
                if disp.supportsBrightness {
                    let bSliderItem = NSMenuItem()
                    bSliderItem.view = makeDisplaySliderView(
                        symbol: "sun.max",
                        initialValue: disp.brightness,
                        onChange: { [weak self] val in
                            self?.displayManager.setBrightness(val, for: disp.displayID, isBuiltIn: disp.isBuiltIn, externalIndex: currentExtIdx)
                        }
                    )
                    displaysMenu.addItem(bSliderItem)
                } else if !disp.isBuiltIn {
                    let noDDC = NSMenuItem(title: "DDC/CI not available on this display", action: nil, keyEquivalent: "")
                    noDDC.isEnabled = false
                    displaysMenu.addItem(noDDC)
                }
                
                if disp.supportsVolume {
                    let vSliderItem = NSMenuItem()
                    vSliderItem.view = makeDisplaySliderView(
                        symbol: "speaker.wave.2",
                        initialValue: disp.volume,
                        onChange: { [weak self] val in
                            self?.displayManager.setVolume(val, for: disp.displayID, externalIndex: currentExtIdx)
                        }
                    )
                    displaysMenu.addItem(vSliderItem)
                }
            }
        }
        let displaysSub = NSMenuItem(title: "Displays & Brightness", action: nil, keyEquivalent: "")
        displaysSub.image = NSImage(systemSymbolName: "display", accessibilityDescription: nil)
        displaysSub.submenu = displaysMenu
        menu.addItem(displaysSub)
        
        // 7. Audio Devices Submenus
        let (inputs, outputs) = audioManager.getDevices()
        
        let outputMenu = NSMenu()
        for dev in outputs {
            let item = NSMenuItem(title: dev.name, action: #selector(selectOutputDevice(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int(dev.deviceID)
            item.state = dev.isDefaultOutput ? .on : .off
            outputMenu.addItem(item)
        }
        let outputSub = NSMenuItem(title: "Audio Output", action: nil, keyEquivalent: "")
        outputSub.image = NSImage(systemSymbolName: "headphones", accessibilityDescription: nil)
        outputSub.submenu = outputMenu
        menu.addItem(outputSub)
        
        let inputMenu = NSMenu()
        for dev in inputs {
            let item = NSMenuItem(title: dev.name, action: #selector(selectInputDevice(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int(dev.deviceID)
            item.state = dev.isDefaultInput ? .on : .off
            inputMenu.addItem(item)
        }
        let inputSub = NSMenuItem(title: "Audio Input", action: nil, keyEquivalent: "")
        inputSub.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)
        inputSub.submenu = inputMenu
        menu.addItem(inputSub)
        
        // 8. Listening Ports Submenu
        let ports = portReader.readListeningPorts()
        let portsMenu = NSMenu()
        if ports.isEmpty {
            let empty = NSMenuItem(title: "No listening ports detected", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            portsMenu.addItem(empty)
        } else {
            for port in ports.prefix(15) {
                let item = NSMenuItem(title: "\(port.processName) on :\(port.port) (PID \(port.pid))", action: #selector(killPortProcess(_:)), keyEquivalent: "")
                item.target = self
                item.tag = Int(port.pid)
                item.toolTip = "Click to terminate process \(port.pid)"
                if let iconPath = port.iconPath {
                    item.image = NSWorkspace.shared.icon(forFile: iconPath)
                } else {
                    item.image = NSImage(systemSymbolName: "network", accessibilityDescription: nil)
                }
                portsMenu.addItem(item)
            }
        }
        let portsSub = NSMenuItem(title: "Listening Ports (\(ports.count) active)", action: nil, keyEquivalent: "")
        portsSub.image = NSImage(systemSymbolName: "network.badge.shield.half.filled", accessibilityDescription: nil)
        portsSub.submenu = portsMenu
        menu.addItem(portsSub)
        
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Quick Tools Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        if let update = MenuActionsHandler.shared.updateItem() { menu.addItem(.separator()); menu.addItem(update) }
        let quit = NSMenuItem(title: "Quit MacUtils", action: #selector(MenuActionsHandler.quitApp), keyEquivalent: "q")
        quit.target = MenuActionsHandler.shared
        menu.addItem(quit)
    }
    
    private func makeDisplaySliderView(symbol: String, initialValue: Int, onChange: @escaping @MainActor (Int) -> Void) -> NSView {
        return DisplaySliderMenuView(symbol: symbol, initialValue: initialValue, onChange: onChange)
    }
    
    @objc private func toggleMicMute() {
        audioManager.toggleInputMute()
        refreshIcon()
    }
    
    @objc private func toggleCleanDesktop() {
        desktopManager.toggle()
        refreshIcon()
    }
    
    @objc private func openScratchpad() {
        ScratchpadWindowController.shared.showScratchpad()
    }
    
    @objc private func extractTextOCR() {
        ScreenTextExtractor.shared.extractTextFromScreen()
    }
    
    @objc private func pickColor() {
        ScreenColorPicker.shared.pickColor()
    }
    
    @objc private func selectOutputDevice(_ sender: NSMenuItem) {
        audioManager.setDefaultOutputDevice(UInt32(sender.tag))
    }
    
    @objc private func selectInputDevice(_ sender: NSMenuItem) {
        audioManager.setDefaultInputDevice(UInt32(sender.tag))
    }
    
    @objc private func killPortProcess(_ sender: NSMenuItem) {
        let pid = Int32(sender.tag)
        _ = portReader.killProcess(pid: pid)
    }
    
    @objc private func openSettings() {
        PreferencesWindowController.shared.showPreferences(selecting: .tools)
    }
}

@MainActor
private final class DisplaySliderMenuView: NSView {
    private let slider = NSSlider()
    private let valueLabel = NSTextField(labelWithString: "75%")
    private let onChange: @MainActor (Int) -> Void
    
    init(symbol: String, initialValue: Int, onChange: @escaping @MainActor (Int) -> Void) {
        self.onChange = onChange
        super.init(frame: NSRect(x: 0, y: 0, width: 220, height: 28))
        
        let iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        iconView.contentTintColor = .secondaryLabelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)
        
        slider.minValue = 0
        slider.maxValue = 100
        slider.integerValue = initialValue
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderChanged)
        slider.controlSize = .small
        slider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(slider)
        
        valueLabel.stringValue = "\(initialValue)%"
        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(valueLabel)
        
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),
            
            slider.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            slider.centerYAnchor.constraint(equalTo: centerYAnchor),
            slider.trailingAnchor.constraint(equalTo: valueLabel.leadingAnchor, constant: -8),
            
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueLabel.widthAnchor.constraint(equalToConstant: 32)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }
    
    @objc private func sliderChanged() {
        let val = slider.integerValue
        valueLabel.stringValue = "\(val)%"
        onChange(val)
    }
}
