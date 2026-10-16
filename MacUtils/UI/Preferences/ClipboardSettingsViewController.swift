import AppKit

@MainActor
final class ClipboardSettingsViewController: SettingsPageViewController {
    private let prefs = AppPreferences.shared
    private let store = ClipboardStore.shared
    
    private lazy var enableSwitch = makeSwitch(on: prefs.clipboardEnabled, action: #selector(enabledChanged))
    private lazy var iconSwitch = makeSwitch(on: prefs.showClipboardIcon, action: #selector(iconChanged))
    private lazy var pauseSwitch = makeSwitch(on: prefs.clipboardPaused, action: #selector(pausedChanged))
    private lazy var richSwitch = makeSwitch(on: prefs.clipboardCaptureRich, action: #selector(richChanged))
    private let limitSlider = NSSlider(value: 30, minValue: 5, maxValue: 100, target: nil, action: nil)
    private let limitLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")
    private let shortcutStatus = NSTextField(labelWithString: "")
    private let accessStatus = NSTextField(labelWithString: "")
    private var setupBanner = NSView()
    private lazy var accessButton = makeButton("Open Accessibility Settings", action: #selector(grantAccess), primary: true)
    
    override var pageTitle: String { "Clipboard" }
    override var pageSubtitle: String { "Copy as usual. Hold ⌘⇧ and press V to choose from everything you copied." }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        observe(ClipboardStore.didChange)
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }
    
    override func buildCards() -> [NSView] {
        let caps = NSStackView(views: [keyCap("⌘"), keyCap("⇧"), keyCap("V")])
        caps.orientation = .horizontal
        caps.spacing = 8
        let steps = SettingsLayout.paragraph("Hold ⌘⇧ and press V to open your history.\nKeep holding and press V again to pick another.\nLet go to paste. Esc cancels.")
        let hero = NSStackView(views: [caps, steps])
        hero.orientation = .horizontal
        hero.alignment = .centerY
        hero.spacing = 24
        hero.distribution = .fill
        steps.setContentHuggingPriority(.init(1), for: .horizontal)
        
        limitSlider.integerValue = prefs.clipboardMaxItems
        limitSlider.target = self
        limitSlider.action = #selector(limitChanged)
        limitSlider.translatesAutoresizingMaskIntoConstraints = false
        limitSlider.widthAnchor.constraint(equalToConstant: 150).isActive = true
        limitLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        limitLabel.textColor = .secondaryLabelColor
        limitLabel.alignment = .right
        limitLabel.translatesAutoresizingMaskIntoConstraints = false
        limitLabel.widthAnchor.constraint(equalToConstant: 64).isActive = true
        limitLabel.stringValue = "\(prefs.clipboardMaxItems) items"
        let limitControl = NSStackView(views: [limitSlider, limitLabel])
        limitControl.orientation = .horizontal
        limitControl.spacing = 8
        
        for l in [shortcutStatus, accessStatus, countLabel] { l.font = NSFont.systemFont(ofSize: 12.5) }
        countLabel.textColor = .secondaryLabelColor
                let clear = makeButton("Clear History", action: #selector(clearHistory))
        let countControl = NSStackView(views: [countLabel, clear])
        countControl.orientation = .horizontal
        countControl.spacing = 12
        
        // Shown only until paste permission is granted.
        let setupTitle = NSTextField(labelWithString: "One more step")
        setupTitle.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        let setupText = SettingsLayout.paragraph("To paste for you when you let go of the keys, macOS needs you to allow MacUtils in Accessibility. Until then, the item is copied and you press ⌘V yourself.")
        setupBanner = SettingsLayout.card(title: nil, [setupTitle, setupText, accessButton])
        accessButton.title = "Open Accessibility Settings"
        
        return [
            setupBanner,
            SettingsLayout.card(title: nil, [
                SettingsLayout.toggleRow("Clipboard history", detail: "Remembers what you copy so you can paste it again.", control: enableSwitch),
                SettingsLayout.divider(),
                hero
            ]),
            SettingsLayout.card(title: "Options", [
                SettingsLayout.toggleRow("Show icon in the menu bar", detail: "Click it to see recent copies and paste one.", control: iconSwitch),
                SettingsLayout.divider(),
                SettingsLayout.toggleRow("Remember images and files", detail: "Turn off to keep text only.", control: richSwitch),
                SettingsLayout.divider(),
                SettingsLayout.toggleRow("How many to remember", control: limitControl),
                SettingsLayout.divider(),
                SettingsLayout.toggleRow("Pause", detail: "Stop remembering new copies for now.", control: pauseSwitch)
            ]),
            SettingsLayout.card(title: "Privacy", [
                SettingsLayout.toggleRow("History stays on this Mac, in memory only", detail: "It is never saved to disk and disappears when you quit. Passwords copied from password managers are ignored.", control: countControl)
            ])
        ]
    }
    
    override func refresh() {
        guard isViewLoaded else { return }
        enableSwitch.state = prefs.clipboardEnabled ? .on : .off
        iconSwitch.state = prefs.showClipboardIcon ? .on : .off
        pauseSwitch.state = prefs.clipboardPaused ? .on : .off
        richSwitch.state = prefs.clipboardCaptureRich ? .on : .off
        let n = store.items.count
        countLabel.stringValue = "\(n) item\(n == 1 ? "" : "s")"
        
        if !prefs.clipboardEnabled {
            shortcutStatus.stringValue = "Off"
            shortcutStatus.textColor = .secondaryLabelColor
        } else if ClipboardPicker.shared.isShortcutActive {
            shortcutStatus.stringValue = "● ⌘⇧V is active"
            shortcutStatus.textColor = .systemGreen
        } else {
            shortcutStatus.stringValue = "● In use by another app"
            shortcutStatus.textColor = .systemOrange
        }
        setupBanner.isHidden = PasteService.hasAccess || !prefs.clipboardEnabled
    }
    
    @objc private func enabledChanged() { prefs.clipboardEnabled = enableSwitch.state == .on; refreshSoon() }
    @objc private func iconChanged() { prefs.showClipboardIcon = iconSwitch.state == .on }
    @objc private func pausedChanged() { prefs.clipboardPaused = pauseSwitch.state == .on }
    @objc private func richChanged() { prefs.clipboardCaptureRich = richSwitch.state == .on }
    @objc private func limitChanged() {
        let v = max(5, Int((limitSlider.doubleValue / 5).rounded()) * 5)
        limitLabel.stringValue = "\(v) items"
        prefs.clipboardMaxItems = v
        store.trimToLimit()
    }
    @objc private func clearHistory() { store.clear() }
    @objc private func grantAccess() { PasteService.openAccessibilitySettings() }
    
    /// The hot key is (un)registered asynchronously after a preference change.
    private func refreshSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.refresh() }
    }
}
