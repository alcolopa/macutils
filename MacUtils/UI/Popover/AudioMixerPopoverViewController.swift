import AppKit

@MainActor
public final class AudioMixerPopoverViewController: NSViewController {
    private let perAppManager = PerAppAudioManager.shared
    private let audioHardware = AudioHardwareManager.shared
    
    private let scrollView = NSScrollView()
    private let container = FlippedStackView()
    
    private let deviceCard = MetricCardView(title: "Audio Output & Mic")
    private let outputPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let micMuteBtn = NSButton(title: "Mute Mic", target: nil, action: nil)
    private var outputDevices: [AudioDeviceItem] = []
    
    private let appsCard = MetricCardView(title: "Per-App Volume", contentInsets: NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8))
    private let appsStack = NSStackView()
    private var rowViews: [String: AppVolumeRowView] = [:]
    private var currentOrder: [String] = []
    
    private var refreshTimer: Timer?
    
    public override func loadView() {
        let root = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 350, height: 460))
        root.material = .popover
        root.blendingMode = .behindWindow
        root.state = .active
        self.view = root
        setupLayout()
    }
    
    public override func viewWillAppear() {
        super.viewWillAppear()
        refreshAll(forceRebuild: true)
        startRefreshTimer()
    }
    
    public override func viewWillDisappear() {
        super.viewWillDisappear()
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAll(forceRebuild: false) }
        }
    }
    
    private func setupLayout() {
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        
        container.orientation = .vertical
        container.alignment = .width
        container.spacing = 12
        container.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let clipView = NSClipView()
        clipView.drawsBackground = false
        clipView.documentView = container
        scrollView.contentView = clipView
        
        // 1. Output Device + Mic Mute Card
        outputPopup.target = self
        outputPopup.action = #selector(outputDeviceChanged)
        outputPopup.controlSize = .small
        outputPopup.translatesAutoresizingMaskIntoConstraints = false
        
        micMuteBtn.target = self
        micMuteBtn.action = #selector(toggleMicMute)
        micMuteBtn.bezelStyle = .rounded
        micMuteBtn.controlSize = .small
        micMuteBtn.translatesAutoresizingMaskIntoConstraints = false
        
        let deviceRow = NSStackView(views: [outputPopup, micMuteBtn])
        deviceRow.orientation = .horizontal
        deviceRow.spacing = 8
        deviceRow.alignment = .centerY
        deviceCard.addContentSubview(deviceRow)
        container.addArrangedSubview(deviceCard)
        
        // 2. Per-App Volume Card
        appsStack.orientation = .vertical
        appsStack.alignment = .width
        appsStack.spacing = 10
        appsCard.addContentSubview(appsStack)
        container.addArrangedSubview(appsCard)
        
        // 3. Footer Actions
        let resetBtn = NSButton(title: "Reset All to 100%", target: self, action: #selector(resetAll))
        resetBtn.bezelStyle = .rounded
        resetBtn.controlSize = .small
        
        let soundSettingsBtn = NSButton(title: "Sound Settings…", target: self, action: #selector(openSoundSettings))
        soundSettingsBtn.bezelStyle = .rounded
        soundSettingsBtn.controlSize = .small
        
        let footer = NSStackView(views: [resetBtn, soundSettingsBtn])
        footer.orientation = .horizontal
        footer.distribution = .fillEqually
        footer.spacing = 8
        container.addArrangedSubview(footer)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            container.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])
    }
    
    public func refreshAll(forceRebuild: Bool) {
        refreshOutputAndMic()
        refreshApps(forceRebuild: forceRebuild)
    }
    
    private func refreshOutputAndMic() {
        let (_, outputs) = audioHardware.getDevices()
        outputDevices = outputs
        outputPopup.removeAllItems()
        var selectedIdx = 0
        for (i, dev) in outputs.enumerated() {
            outputPopup.addItem(withTitle: dev.name)
            if dev.isDefaultOutput { selectedIdx = i }
        }
        if !outputs.isEmpty {
            outputPopup.selectItem(at: selectedIdx)
        }
        
        let muted = audioHardware.isInputMuted()
        micMuteBtn.title = muted ? "Mic Muted" : "Mute Mic"
        micMuteBtn.contentTintColor = muted ? .systemOrange : nil
    }
    
    private func refreshApps(forceRebuild: Bool) {
        guard PerAppAudioManager.isSupported else {
            appsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
            let label = NSTextField(wrappingLabelWithString: "Per-app volume control requires macOS 14.2 or later.")
            label.font = NSFont.systemFont(ofSize: 11.5)
            label.textColor = .secondaryLabelColor
            appsStack.addArrangedSubview(label)
            return
        }
        
        let apps = perAppManager.listAudioApps()
        let activeCount = apps.filter(\.isPlaying).count
        appsCard.setBadge(activeCount > 0 ? "\(activeCount) playing" : "\(apps.count) apps")
        
        if apps.isEmpty {
            appsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
            rowViews.removeAll()
            currentOrder.removeAll()
            let empty = NSTextField(wrappingLabelWithString: "No audio apps detected yet. Start playing audio in an app (like Spotify or Chrome) and it will appear here.")
            empty.font = NSFont.systemFont(ofSize: 11.5)
            empty.textColor = .secondaryLabelColor
            appsStack.addArrangedSubview(empty)
            return
        }
        
        let newOrder = apps.map(\.key)
        if !forceRebuild && newOrder == currentOrder {
            // Update existing rows in place so dragging a slider is never interrupted
            for app in apps {
                rowViews[app.key]?.update(item: app)
            }
            return
        }
        
        currentOrder = newOrder
        appsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        rowViews.removeAll()
        
        for app in apps {
            let row = AppVolumeRowView(
                item: app,
                onVolumeChange: { [weak self] newVol in
                    self?.perAppManager.setVolume(newVol, for: app.key, objectIDs: app.objectIDs)
                },
                onToggleMute: { [weak self] in
                    self?.perAppManager.toggleMute(for: app.key, objectIDs: app.objectIDs)
                    self?.refreshApps(forceRebuild: false)
                }
            )
            rowViews[app.key] = row
            appsStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: appsStack.widthAnchor).isActive = true
        }
    }
    
    @objc private func outputDeviceChanged() {
        let idx = outputPopup.indexOfSelectedItem
        guard idx >= 0 && idx < outputDevices.count else { return }
        audioHardware.setDefaultOutputDevice(outputDevices[idx].deviceID)
    }
    
    @objc private func toggleMicMute() {
        audioHardware.toggleInputMute()
        refreshOutputAndMic()
    }
    
    @objc private func resetAll() {
        perAppManager.resetAll()
        refreshApps(forceRebuild: true)
    }
    
    @objc private func openSoundSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

@MainActor
private final class AppVolumeRowView: NSView {
    private let iconView = NSImageView()
    private let playingDot = NSView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let muteButton = NSButton()
    private let slider = NSSlider()
    private let valueLabel = NSTextField(labelWithString: "100%")
    
    private let onVolumeChange: @MainActor (Float) -> Void
    private let onToggleMute: @MainActor () -> Void
    
    init(
        item: AppAudioItem,
        onVolumeChange: @escaping @MainActor (Float) -> Void,
        onToggleMute: @escaping @MainActor () -> Void
    ) {
        self.onVolumeChange = onVolumeChange
        self.onToggleMute = onToggleMute
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setupUI()
        update(item: item)
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }
    
    private func setupUI() {
        heightAnchor.constraint(equalToConstant: 42).isActive = true
        
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)
        
        playingDot.wantsLayer = true
        playingDot.layer?.cornerRadius = 3
        playingDot.layer?.backgroundColor = NSColor.systemGreen.cgColor
        playingDot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(playingDot)
        
        nameLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)
        
        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(valueLabel)
        
        muteButton.isBordered = false
        muteButton.imagePosition = .imageOnly
        muteButton.target = self
        muteButton.action = #selector(muteClicked)
        muteButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(muteButton)
        
        slider.minValue = 0
        slider.maxValue = 100
        slider.isContinuous = true
        slider.controlSize = .small
        slider.target = self
        slider.action = #selector(sliderChanged)
        slider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(slider)
        
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            
            playingDot.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            playingDot.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            playingDot.widthAnchor.constraint(equalToConstant: 6),
            playingDot.heightAnchor.constraint(equalToConstant: 6),
            
            nameLabel.leadingAnchor.constraint(equalTo: playingDot.trailingAnchor, constant: 5),
            nameLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: valueLabel.leadingAnchor, constant: -6),
            
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            valueLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            valueLabel.widthAnchor.constraint(equalToConstant: 42),
            
            muteButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            muteButton.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 4),
            muteButton.widthAnchor.constraint(equalToConstant: 18),
            muteButton.heightAnchor.constraint(equalToConstant: 16),
            
            slider.leadingAnchor.constraint(equalTo: muteButton.trailingAnchor, constant: 6),
            slider.centerYAnchor.constraint(equalTo: muteButton.centerYAnchor),
            slider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2)
        ])
    }
    
    func update(item: AppAudioItem) {
        if let app = NSRunningApplication(processIdentifier: item.leadPid), let icon = app.icon {
            iconView.image = icon
        } else if let path = item.iconPath {
            iconView.image = NSWorkspace.shared.icon(forFile: path)
        } else {
            iconView.image = NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil)
        }
        
        playingDot.isHidden = !item.isPlaying
        nameLabel.stringValue = item.name
        
        let pct = Int((item.volume * 100.0).rounded())
        if !slider.isHighlighted {
            slider.integerValue = item.isMuted ? 0 : pct
        }
        valueLabel.stringValue = item.isMuted ? "Muted" : "\(pct)%"
        valueLabel.textColor = item.isMuted ? .systemOrange : .secondaryLabelColor
        
        let symName = item.isMuted || pct == 0 ? "speaker.slash.fill" : (pct < 50 ? "speaker.wave.1.fill" : "speaker.wave.2.fill")
        muteButton.image = NSImage(systemSymbolName: symName, accessibilityDescription: "Mute")
        muteButton.contentTintColor = item.isMuted ? .systemOrange : .secondaryLabelColor
    }
    
    @objc private func sliderChanged() {
        let pct = slider.integerValue
        valueLabel.stringValue = "\(pct)%"
        valueLabel.textColor = .secondaryLabelColor
        let symName = pct == 0 ? "speaker.slash.fill" : (pct < 50 ? "speaker.wave.1.fill" : "speaker.wave.2.fill")
        muteButton.image = NSImage(systemSymbolName: symName, accessibilityDescription: "Mute")
        muteButton.contentTintColor = .secondaryLabelColor
        onVolumeChange(Float(pct) / 100.0)
    }
    
    @objc private func muteClicked() {
        onToggleMute()
    }
}
