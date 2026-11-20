import AppKit

@MainActor
final class ToolsSettingsViewController: SettingsPageViewController {
    private let prefs = AppPreferences.shared
    private let audioManager = AudioHardwareManager.shared
    private let desktopManager = CleanDesktopManager.shared
    
    private lazy var showSwitch = makeSwitch(on: prefs.showTools, action: #selector(showChanged))
    private lazy var showMixerSwitch = makeSwitch(on: prefs.showAudioMixer, action: #selector(showMixerChanged))
    private lazy var hotkeysSwitch = makeSwitch(on: prefs.toolsHotkeysEnabled, action: #selector(hotkeysChanged))
    private lazy var micMuteSwitch = makeSwitch(on: audioManager.isInputMuted(), action: #selector(micMuteChanged))
    private lazy var cleanDesktopSwitch = makeSwitch(on: desktopManager.areIconsHidden, action: #selector(cleanDesktopChanged))
    private let colorFormatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    
    override var pageTitle: String { "Quick Tools" }
    override var pageSubtitle: String { "OCR text grabber, color picker, scratchpad, mic mute, clean desktop, audio switcher, listening ports, and display DDC/CI controls." }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        observe(AudioHardwareManager.didChange)
        observe(CleanDesktopManager.didChange)
    }
    
    override func buildCards() -> [NSView] {
        colorFormatPopup.removeAllItems()
        for fmt in ColorPickerFormat.allCases {
            colorFormatPopup.addItem(withTitle: "\(fmt.rawValue) (\(fmt.example))")
        }
        colorFormatPopup.selectItem(at: ColorPickerFormat.allCases.firstIndex(of: prefs.colorPickerFormat) ?? 0)
        colorFormatPopup.target = self
        colorFormatPopup.action = #selector(colorFormatChanged)
        
        var shortcutRows: [NSView] = [
            SettingsLayout.toggleRow("Enable global hotkeys", detail: "Trigger Quick Tools from anywhere without opening the menu bar.", control: hotkeysSwitch)
        ]
        for sc in QuickToolsHotkeys.shortcuts {
            shortcutRows.append(SettingsLayout.divider())
            let badge = NSTextField(labelWithString: sc.display)
            badge.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
            badge.textColor = .secondaryLabelColor
            badge.alignment = .right
            shortcutRows.append(SettingsLayout.toggleRow(sc.title, control: badge))
        }
        
        return [
            SettingsLayout.card(title: "Menu bar", [
                SettingsLayout.toggleRow("Show Quick Tools in the menu bar", detail: "Icon turns green/orange when camera or microphone is active, or orange when mic is muted.", control: showSwitch),
                SettingsLayout.divider(),
                SettingsLayout.toggleRow("Quick Tools position", detail: "Move Quick Tools left or right along the menu bar.", control: makePositionControl(for: .tools)),
                SettingsLayout.divider(),
                SettingsLayout.toggleRow("Show Per-App Audio Mixer in the menu bar", detail: "Adjust volume and mute individually per app (macOS 14.2+).", control: showMixerSwitch),
                SettingsLayout.divider(),
                SettingsLayout.toggleRow("Audio Mixer position", detail: "Move the Audio Mixer left or right along the menu bar.", control: makePositionControl(for: .audioMixer))
            ]),
            SettingsLayout.card(title: "Quick toggles", [
                SettingsLayout.toggleRow("Mute microphone", detail: "Hardware-mutes the default audio input device.", control: micMuteSwitch),
                SettingsLayout.divider(),
                SettingsLayout.toggleRow("Clean desktop mode", detail: "Hides desktop icons for screen sharing and presentations.", control: cleanDesktopSwitch),
                SettingsLayout.divider(),
                SettingsLayout.toggleRow("Color picker format", detail: "Format copied to clipboard when sampling a screen color.", control: colorFormatPopup)
            ]),
            SettingsLayout.card(title: "Global shortcuts", shortcutRows)
        ]
    }
    
    override func refresh() {
        guard isViewLoaded else { return }
        showSwitch.state = prefs.showTools ? .on : .off
        showMixerSwitch.state = prefs.showAudioMixer ? .on : .off
        hotkeysSwitch.state = prefs.toolsHotkeysEnabled ? .on : .off
        micMuteSwitch.state = audioManager.isInputMuted() ? .on : .off
        cleanDesktopSwitch.state = desktopManager.areIconsHidden ? .on : .off
        colorFormatPopup.selectItem(at: ColorPickerFormat.allCases.firstIndex(of: prefs.colorPickerFormat) ?? 0)
    }
    
    @objc private func showChanged() {
        prefs.showTools = showSwitch.state == .on
    }
    
    @objc private func showMixerChanged() {
        prefs.showAudioMixer = showMixerSwitch.state == .on
    }
    
    @objc private func hotkeysChanged() {
        prefs.toolsHotkeysEnabled = hotkeysSwitch.state == .on
    }
    
    @objc private func micMuteChanged() {
        audioManager.setInputMuted(micMuteSwitch.state == .on)
    }
    
    @objc private func cleanDesktopChanged() {
        desktopManager.setIconsHidden(cleanDesktopSwitch.state == .on)
    }
    
    @objc private func colorFormatChanged() {
        let idx = colorFormatPopup.indexOfSelectedItem
        if idx >= 0 && idx < ColorPickerFormat.allCases.count {
            prefs.colorPickerFormat = ColorPickerFormat.allCases[idx]
        }
    }
}
