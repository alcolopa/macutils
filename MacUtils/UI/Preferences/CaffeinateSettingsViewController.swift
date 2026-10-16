import AppKit

@MainActor
final class CaffeinateSettingsViewController: SettingsPageViewController {
    private let prefs = AppPreferences.shared
    private let manager = CaffeinateManager.shared
    
    private let statusIcon = NSImageView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private lazy var toggleButton = makeButton("Turn On", action: #selector(toggleSession), primary: true)
    private lazy var showSwitch = makeSwitch(on: prefs.showCaffeinate, action: #selector(showChanged))
    private lazy var displaySwitch = makeSwitch(on: prefs.caffeinateKeepDisplayAwake, action: #selector(displayChanged))
    private let durationPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    
    override var pageTitle: String { "Caffeinate" }
    override var pageSubtitle: String { "Keep your Mac awake while you work, download or present. No other app needed." }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        observe(CaffeinateManager.didChange)
    }
    
    override func buildCards() -> [NSView] {
        statusIcon.symbolConfiguration = .init(pointSize: 26, weight: .regular)
        statusIcon.translatesAutoresizingMaskIntoConstraints = false
        statusIcon.widthAnchor.constraint(equalToConstant: 40).isActive = true
        statusLabel.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        detailLabel.font = NSFont.systemFont(ofSize: 12.5)
        detailLabel.textColor = .secondaryLabelColor
        let text = NSStackView(views: [statusLabel, detailLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        let top = NSStackView(views: [statusIcon, text, SettingsLayout.spacer(), toggleButton])
        top.orientation = .horizontal
        top.alignment = .centerY
        top.spacing = 12
        
        let quickCaption = NSTextField(labelWithString: "Keep awake for")
        quickCaption.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let quick = NSStackView()
        quick.orientation = .horizontal
        quick.spacing = 8
        for (index, preset) in CaffeinateManager.presets.enumerated() {
            let b = makeButton(preset.seconds.map(Self.shortTitle) ?? "∞", action: #selector(startPreset(_:)))
            b.tag = index
            b.toolTip = preset.title
            quick.addArrangedSubview(b)
        }
        quick.addArrangedSubview(SettingsLayout.spacer())
        
        durationPopup.removeAllItems()
        for preset in CaffeinateManager.presets { durationPopup.addItem(withTitle: preset.title) }
        let current = prefs.caffeinateDefaultDuration
        durationPopup.selectItem(at: CaffeinateManager.presets.firstIndex { ($0.seconds ?? 0) == current } ?? CaffeinateManager.presets.count - 1)
        durationPopup.target = self
        durationPopup.action = #selector(durationChanged)
        
        return [
            SettingsLayout.card(title: nil, [top, SettingsLayout.divider(), quickCaption, quick]),
            SettingsLayout.card(title: "Menu bar", [
                SettingsLayout.toggleRow("Show the cup in the menu bar", detail: "Click it to turn Caffeinate on or off. Right-click for more options. A running timer shows the time left.", control: showSwitch),
                SettingsLayout.divider(),
                SettingsLayout.toggleRow("When I click the cup, stay awake", detail: "Used by a plain click. Right-click lets you pick any duration.", control: durationPopup)
            ]),
            SettingsLayout.card(title: nil, [
                SettingsLayout.toggleRow("Keep the display awake too", detail: "Off lets the screen dim and turn off while the Mac keeps running. Closing a laptop lid still sleeps it.", control: displaySwitch)
            ])
        ]
    }
    
    private static func shortTitle(_ seconds: TimeInterval) -> String {
        seconds < 3600 ? "\(Int(seconds / 60)) min" : "\(Int(seconds / 3600)) h"
    }
    
    override func refresh() {
        guard isViewLoaded else { return }
        if manager.isActive {
            statusLabel.stringValue = "Your Mac is staying awake"
            if let end = manager.endDate {
                let f = DateFormatter(); f.timeStyle = .short
                detailLabel.stringValue = "Until \(f.string(from: end))"
            } else {
                detailLabel.stringValue = "Until you turn it off"
            }
            toggleButton.title = "Turn Off"
            statusIcon.image = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: nil)
            statusIcon.contentTintColor = .controlAccentColor
        } else {
            statusLabel.stringValue = "Caffeinate is off"
            detailLabel.stringValue = "Your Mac sleeps normally"
            toggleButton.title = "Turn On"
            statusIcon.image = NSImage(systemSymbolName: "cup.and.saucer", accessibilityDescription: nil)
            statusIcon.contentTintColor = .secondaryLabelColor
        }
        showSwitch.state = prefs.showCaffeinate ? .on : .off
        displaySwitch.state = prefs.caffeinateKeepDisplayAwake ? .on : .off
    }
    
    @objc private func toggleSession() {
        manager.isActive ? manager.stop() : manager.startDefault()
    }
    
    @objc private func startPreset(_ sender: NSButton) {
        manager.start(duration: CaffeinateManager.presets[sender.tag].seconds, keepDisplayAwake: prefs.caffeinateKeepDisplayAwake)
    }
    
    @objc private func showChanged() { prefs.showCaffeinate = showSwitch.state == .on }
    
    @objc private func displayChanged() {
        prefs.caffeinateKeepDisplayAwake = displaySwitch.state == .on
        if manager.isActive {
            let remaining = manager.endDate.map { max(1, $0.timeIntervalSinceNow) }
            manager.start(duration: remaining, keepDisplayAwake: prefs.caffeinateKeepDisplayAwake)
        }
    }
    
    @objc private func durationChanged() {
        prefs.caffeinateDefaultDuration = CaffeinateManager.presets[durationPopup.indexOfSelectedItem].seconds ?? 0
    }
}
