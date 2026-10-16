import AppKit
import ServiceManagement

@MainActor
final class GeneralSettingsViewController: SettingsPageViewController {
    private let prefs = AppPreferences.shared
    private lazy var loginSwitch = makeSwitch(on: false, action: #selector(loginToggled))
    private lazy var autoUpdateSwitch = makeSwitch(on: AppPreferences.shared.autoCheckUpdates, action: #selector(autoUpdateToggled))
    private let updateTitle = NSTextField(labelWithString: "")
    private let updateDetail = NSTextField(wrappingLabelWithString: "")
    private lazy var updateButton = makeButton("Check for Updates", action: #selector(updateButtonClicked), primary: true)
    private let updateProgress = NSProgressIndicator()
    private let themePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let paddingSlider = NSSlider(value: 0, minValue: 0, maxValue: 12, target: nil, action: nil)
    private let paddingLabel = NSTextField(labelWithString: "")
    private let intervalSlider = NSSlider(value: 1.5, minValue: 0.25, maxValue: 5.0, target: nil, action: nil)
    private let intervalLabel = NSTextField(labelWithString: "")
    
    override var pageTitle: String { "General" }
    override var pageSubtitle: String { "MacUtils lives in your menu bar and stays out of your way." }
    
    override func buildCards() -> [NSView] {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let github = makeButton("GitHub", action: #selector(openGitHub))
        let releases = makeButton("Releases", action: #selector(openReleases))
        let links = NSStackView(views: [github, releases])
        links.orientation = .horizontal
        links.spacing = 8
        themePopup.removeAllItems()
        for theme in ColorTheme.allCases { themePopup.addItem(withTitle: theme.rawValue) }
        themePopup.selectItem(withTitle: prefs.colorTheme.rawValue)
        themePopup.target = self
        themePopup.action = #selector(themeChanged)
        
        paddingSlider.doubleValue = prefs.barOptions(for: .cpu).padding
        paddingSlider.target = self
        paddingSlider.action = #selector(paddingChanged)
        paddingLabel.stringValue = "\(Int(paddingSlider.doubleValue)) pt"
        intervalSlider.doubleValue = prefs.passiveInterval
        intervalSlider.target = self
        intervalSlider.action = #selector(intervalChanged)
        intervalLabel.stringValue = String(format: "%.1f s", prefs.passiveInterval)
        
        func slider(_ s: NSSlider, _ l: NSTextField) -> NSView {
            l.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            l.textColor = .secondaryLabelColor
            l.alignment = .right
            l.translatesAutoresizingMaskIntoConstraints = false
            l.widthAnchor.constraint(equalToConstant: 48).isActive = true
            s.translatesAutoresizingMaskIntoConstraints = false
            s.widthAnchor.constraint(equalToConstant: 160).isActive = true
            let stack = NSStackView(views: [s, l])
            stack.orientation = .horizontal
            stack.spacing = 8
            return stack
        }
        
        return [
            SettingsLayout.card(title: "System monitor look", [
                SettingsLayout.toggleRow("Colours", detail: "Used in graphs and bars when you click a monitor.", control: themePopup),
                SettingsLayout.divider(),
                SettingsLayout.toggleRow("Spacing", detail: "Space around each monitor in the menu bar.", control: slider(paddingSlider, paddingLabel)),
                SettingsLayout.divider(),
                SettingsLayout.toggleRow("Refresh speed", detail: "Lower is smoother, higher saves battery.", control: slider(intervalSlider, intervalLabel))
            ]),
            updatesCard(),
            SettingsLayout.card(title: "Startup", [
                SettingsLayout.toggleRow("Open MacUtils at login", detail: "Works best when MacUtils.app is in /Applications.", control: loginSwitch)
            ]),
            SettingsLayout.card(title: "About", [
                SettingsLayout.toggleRow("MacUtils \(version)", detail: "Free and open source. Clipboard manager, Caffeinate and a system monitor in one small menu bar app.", control: links)
            ])
        ]
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        observe(UpdateManager.didChange)
    }
    
    private func updatesCard() -> NSView {
        updateTitle.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        updateDetail.font = NSFont.systemFont(ofSize: 11.5)
        updateDetail.textColor = .secondaryLabelColor
        updateDetail.isSelectable = false
        updateProgress.style = .bar
        updateProgress.isIndeterminate = false
        updateProgress.minValue = 0
        updateProgress.maxValue = 1
        updateProgress.isHidden = true
        updateProgress.translatesAutoresizingMaskIntoConstraints = false
        
        let texts = NSStackView(views: [updateTitle, updateDetail])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 2
        let top = NSStackView(views: [texts, SettingsLayout.spacer(), updateButton])
        top.orientation = .horizontal
        top.alignment = .centerY
        top.spacing = 20
        return SettingsLayout.card(title: "Updates", [
            top,
            updateProgress,
            SettingsLayout.divider(),
            SettingsLayout.toggleRow("Check automatically", detail: "Looks for a new version once or twice a day.", control: autoUpdateSwitch)
        ])
    }
    
    private func refreshUpdates() {
        let manager = UpdateManager.shared
        updateProgress.isHidden = true
        updateButton.isEnabled = true
        updateTitle.stringValue = "MacUtils \(manager.currentVersion)"
        switch manager.state {
        case .idle:
            updateDetail.stringValue = "Check whether a newer version is available."
            updateButton.title = "Check for Updates"
        case .checking:
            updateDetail.stringValue = "Checking…"
            updateButton.title = "Check for Updates"
            updateButton.isEnabled = false
        case .upToDate:
            updateDetail.stringValue = "You're up to date."
            updateButton.title = "Check Again"
        case .available(let release):
            updateTitle.stringValue = "MacUtils \(release.version) is available"
            updateDetail.stringValue = manager.canInstall ? "You have \(manager.currentVersion). Installing restarts MacUtils." : "You have \(manager.currentVersion)."
            updateButton.title = manager.canInstall ? "Install and Restart" : "View Release"
        case .downloading(let fraction):
            updateDetail.stringValue = "Downloading… \(Int(fraction * 100))%"
            updateButton.title = "Downloading"
            updateButton.isEnabled = false
            updateProgress.isHidden = false
            updateProgress.doubleValue = fraction
        case .installing:
            updateDetail.stringValue = "Installing… MacUtils will restart."
            updateButton.title = "Installing"
            updateButton.isEnabled = false
        case .failed(let message):
            updateDetail.stringValue = message
            updateButton.title = "Try Again"
        }
    }
    
    @objc private func updateButtonClicked() {
        let manager = UpdateManager.shared
        if let release = manager.availableRelease {
            if manager.canInstall { manager.install() } else { NSWorkspace.shared.open(release.pageURL) }
        } else {
            Task { await manager.check() }
        }
    }
    
    @objc private func autoUpdateToggled() {
        AppPreferences.shared.autoCheckUpdates = autoUpdateSwitch.state == .on
    }
    
    override func refresh() {
        guard isViewLoaded else { return }
        refreshUpdates()
        loginSwitch.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
    
    @objc private func loginToggled() {
        do {
            if loginSwitch.state == .on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn't change login item"
            alert.runModal()
        }
        refresh()
    }
    
    @objc private func themeChanged() {
        guard let title = themePopup.titleOfSelectedItem, let theme = ColorTheme(rawValue: title) else { return }
        prefs.colorTheme = theme
    }
    
    @objc private func paddingChanged() {
        let v = round(paddingSlider.doubleValue)
        paddingLabel.stringValue = "\(Int(v)) pt"
        for m in MetricType.allCases {
            var o = prefs.barOptions(for: m); o.padding = v; prefs.setBarOptions(o, for: m)
        }
    }
    
    @objc private func intervalChanged() {
        prefs.passiveInterval = intervalSlider.doubleValue
        intervalLabel.stringValue = String(format: "%.1f s", intervalSlider.doubleValue)
    }
    
    @objc private func openGitHub() { NSWorkspace.shared.open(URL(string: "https://github.com/alcolopa/macmonitor")!) }
    @objc private func openReleases() { NSWorkspace.shared.open(URL(string: "https://github.com/alcolopa/macmonitor/releases")!) }
}
