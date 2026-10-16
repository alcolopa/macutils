import AppKit

/// One tile in the style picker: a small sample of the widget plus its name.
@MainActor
private final class StyleTileView: NSView {
    var onClick: (() -> Void)?
    
    init(sample: NSView, title: String, selected: Bool) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = selected ? 2 : 1
        layer?.borderColor = (selected ? NSColor.controlAccentColor : NSColor.separatorColor.withAlphaComponent(0.5)).cgColor
        layer?.backgroundColor = (selected ? NSColor.controlAccentColor.withAlphaComponent(0.14) : NSColor.labelColor.withAlphaComponent(0.04)).cgColor
        translatesAutoresizingMaskIntoConstraints = false
        
        let stage = NSView()
        stage.translatesAutoresizingMaskIntoConstraints = false
        sample.translatesAutoresizingMaskIntoConstraints = false
        stage.addSubview(sample)
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 12, weight: selected ? .semibold : .regular)
        label.textColor = selected ? .labelColor : .secondaryLabelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stage)
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 84),
            stage.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stage.leadingAnchor.constraint(equalTo: leadingAnchor),
            stage.trailingAnchor.constraint(equalTo: trailingAnchor),
            stage.heightAnchor.constraint(equalToConstant: 34),
            sample.centerXAnchor.constraint(equalTo: stage.centerXAnchor),
            sample.centerYAnchor.constraint(equalTo: stage.centerYAnchor),
            label.topAnchor.constraint(equalTo: stage.bottomAnchor, constant: 8),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4)
        ])
        setAccessibilityLabel(title)
        setAccessibilityRole(.radioButton)
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
}

/// Settings page for one monitor: on/off, how it looks, where it sits, and its own options.
@MainActor
final class MetricSettingsViewController: SettingsPageViewController {
    private let metric: MetricType
    private let prefs = AppPreferences.shared
    
    private let tileGrid = NSStackView()
    private let positionLabel = NSTextField(labelWithString: "")
    
    private lazy var enableSwitch = makeSwitch(on: prefs.isMetricVisible(metric), action: #selector(onToggleVisibility))
    private lazy var iconSwitch = makeSwitch(on: false, action: #selector(onIconToggled))
    private lazy var labelSwitch = makeSwitch(on: false, action: #selector(onLabelToggled))
    
    private let memModePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let tempUnitPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let apiKeyField = NSSecureTextField()
    private let cityField = NSTextField()
    private let weatherIntervalPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let forecastModePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let testKeyButton = NSButton(title: "Test", target: nil, action: nil)
    private let testStatusLabel = NSTextField(labelWithString: "")
    
    init(metric: MetricType) {
        self.metric = metric
        super.init(nibName: nil, bundle: nil)
        title = metric.displayName
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    override var pageTitle: String { metric.displayName }
    override var pageSubtitle: String {
        switch metric {
        case .cpu: return "How busy your processor and graphics are."
        case .memory: return "How much memory your apps are using."
        case .disk: return "How full your startup disk is."
        case .network: return "Your current upload and download speed."
        case .temperatures: return "How warm your Mac is running."
        case .weather: return "The weather where you are, right in the menu bar."
        }
    }
    
    // MARK: - Layout
    
    override func buildCards() -> [NSView] {
        var cards: [NSView] = [
            SettingsLayout.card(title: nil, [
                SettingsLayout.toggleRow("Show in the menu bar", detail: "Turn this monitor on or off.", control: enableSwitch)
            ])
        ]
        
        tileGrid.orientation = .vertical
        tileGrid.alignment = .leading
        tileGrid.spacing = 10
        tileGrid.distribution = .fill
        
        var appearance: [NSView] = [tileGrid]
        if metric != .weather {
            appearance.append(SettingsLayout.divider())
            appearance.append(SettingsLayout.toggleRow("Show the icon", control: iconSwitch))
        }
        appearance.append(SettingsLayout.divider())
        appearance.append(SettingsLayout.toggleRow("Show the name", detail: "Adds a short label such as \"\(shortName)\" before the value.", control: labelSwitch))
        cards.append(SettingsLayout.card(title: "Style", appearance))
        
        let leftButton = makeButton("◀", action: #selector(positionLeft))
        let rightButton = makeButton("▶", action: #selector(positionRight))
        let arrows = NSStackView(views: [leftButton, rightButton])
        arrows.orientation = .horizontal
        arrows.spacing = 6
        positionLabel.font = NSFont.systemFont(ofSize: 11.5)
        cards.append(SettingsLayout.card(title: nil, [
            SettingsLayout.toggleRow("Position in the menu bar", detail: "Move it left or right among your monitors.", control: arrows)
        ]))
        
        if let options = optionsCard() { cards.append(options) }
        return cards
    }
    
    private var shortName: String {
        switch metric {
        case .cpu: return "CPU"
        case .memory: return "MEM"
        case .disk: return "DSK"
        case .network: return "NET"
        case .temperatures: return "TMP"
        case .weather: return "WX"
        }
    }
    
    private func friendlyName(for style: MetricDisplayStyle) -> String {
        switch style {
        case .textOnly: return metric == .weather ? "Temperature" : "Number"
        case .standard: return metric == .network ? "Up & down" : "Graph"
        case .barOnly: return metric == .weather ? "Icon" : "Bar"
        case .verticalBar: return "Level"
        case .circularGauge: return "Ring"
        case .multicolorCircle: return "Colour ring"
        case .humidity: return "Humidity"
        case .wind: return "Wind"
        case .feelsLike: return "Feels like"
        case .highLow: return "High / low"
        case .rainChance: return "Rain"
        }
    }
    
    private func optionsCard() -> NSView? {
        switch metric {
        case .memory:
            memModePopup.removeAllItems()
            memModePopup.addItems(withTitles: ["Percentage", "Amount used", "Pressure"])
            switch prefs.memoryDisplayMode {
            case .percentage: memModePopup.selectItem(at: 0)
            case .usedAmount: memModePopup.selectItem(at: 1)
            case .pressure:   memModePopup.selectItem(at: 2)
            }
            memModePopup.target = self
            memModePopup.action = #selector(onMemModeChanged)
            return SettingsLayout.card(title: "Options", [
                SettingsLayout.toggleRow("Show memory as", detail: "Percentage, gigabytes used, or how stressed memory is.", control: memModePopup)
            ])
        case .temperatures:
            tempUnitPopup.removeAllItems()
            for unit in TemperatureUnit.allCases { tempUnitPopup.addItem(withTitle: unit.rawValue) }
            tempUnitPopup.selectItem(withTitle: prefs.temperatureUnit.rawValue)
            tempUnitPopup.target = self
            tempUnitPopup.action = #selector(onTempUnitChanged)
            return SettingsLayout.card(title: "Options", [
                SettingsLayout.toggleRow("Temperature unit", control: tempUnitPopup)
            ])
        case .weather:
            apiKeyField.placeholderString = "Paste your key"
            apiKeyField.stringValue = prefs.weatherApiKey
            apiKeyField.target = self
            apiKeyField.action = #selector(onApiKeyChanged)
            apiKeyField.translatesAutoresizingMaskIntoConstraints = false
            apiKeyField.widthAnchor.constraint(equalToConstant: 190).isActive = true
            testKeyButton.bezelStyle = .rounded
            testKeyButton.target = self
            testKeyButton.action = #selector(onTestApiKey)
            testStatusLabel.font = NSFont.systemFont(ofSize: 11.5)
            testStatusLabel.textColor = .secondaryLabelColor
            testStatusLabel.lineBreakMode = .byTruncatingTail
            let keyControl = NSStackView(views: [apiKeyField, testKeyButton])
            keyControl.orientation = .horizontal
            keyControl.spacing = 8
            
            let getKey = NSButton(title: "Get a free key", target: self, action: #selector(openOpenWeatherMapSignup))
            getKey.bezelStyle = .rounded
            
            cityField.placeholderString = "auto"
            cityField.stringValue = prefs.weatherCity
            cityField.target = self
            cityField.action = #selector(onCityChanged)
            cityField.translatesAutoresizingMaskIntoConstraints = false
            cityField.widthAnchor.constraint(equalToConstant: 190).isActive = true
            
            weatherIntervalPopup.removeAllItems()
            weatherIntervalPopup.addItems(withTitles: ["Every 15 minutes", "Every 30 minutes", "Every hour"])
            let sec = prefs.weatherUpdateInterval
            weatherIntervalPopup.selectItem(at: sec <= 900 ? 0 : (sec <= 1800 ? 1 : 2))
            weatherIntervalPopup.target = self
            weatherIntervalPopup.action = #selector(onWeatherIntervalChanged)
            
            forecastModePopup.removeAllItems()
            forecastModePopup.addItems(withTitles: WeatherForecastMode.allCases.map { $0.rawValue })
            forecastModePopup.selectItem(withTitle: prefs.weatherForecastMode.rawValue)
            forecastModePopup.target = self
            forecastModePopup.action = #selector(onForecastModeChanged)
            
            return SettingsLayout.card(title: "Weather setup", [
                SettingsLayout.toggleRow("OpenWeatherMap key", detail: "Weather comes from OpenWeatherMap. A free key is enough.", control: keyControl),
                testStatusLabel,
                getKey,
                SettingsLayout.divider(),
                SettingsLayout.toggleRow("Location", detail: "A city like \"London, UK\", or \"auto\" to use where you are.", control: cityField),
                SettingsLayout.divider(),
                SettingsLayout.toggleRow("Update", control: weatherIntervalPopup),
                SettingsLayout.divider(),
                SettingsLayout.toggleRow("Forecast", detail: "What the weather popover shows.", control: forecastModePopup)
            ])
        default:
            return nil
        }
    }
    
    // MARK: - State
    
    override func refresh() {
        guard isViewLoaded else { return }
        let o = prefs.barOptions(for: metric)
        enableSwitch.state = prefs.isMetricVisible(metric) ? .on : .off
        iconSwitch.state = o.showIcon ? .on : .off
        labelSwitch.state = o.showLabel ? .on : .off
        
        // Style tiles
        tileGrid.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let styles = AppPreferences.availableStyles(for: metric)
        let current = o.styles.first
        let perRow = styles.count <= 5 ? styles.count : 4
        var index = 0
        while index < styles.count {
            let rowStyles = Array(styles[index..<min(index + perRow, styles.count)])
            var tiles: [NSView] = rowStyles.map { style in
                let tile = StyleTileView(sample: SingleMetricWidgetPreviewView.makeSampleMiniView(metric: metric, style: style, theme: .monochrome),
                                         title: friendlyName(for: style), selected: style == current)
                tile.onClick = { [weak self] in self?.select(style) }
                return tile
            }
            while tiles.count < perRow { tiles.append(NSView()) }   // keep tiles the same width on the last row
            let row = NSStackView(views: tiles)
            row.orientation = .horizontal
            row.spacing = 10
            row.distribution = .fillEqually
            tileGrid.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: tileGrid.widthAnchor).isActive = true
            index += perRow
        }
    }
    
    private func select(_ style: MetricDisplayStyle) {
        prefs.setDisplayStyle(style, for: metric)
        refresh()
    }
    
    private func setPart(_ part: BarPart, on: Bool) {
        var o = prefs.barOptions(for: metric)
        o.order.removeAll { $0 == part }
        if on { o.order.insert(part, at: part == .icon ? 0 : (o.order.first == .icon ? 1 : 0)) }
        prefs.setBarOptions(o, for: metric)
        refresh()
    }
    
    @objc private func onIconToggled() { setPart(.icon, on: iconSwitch.state == .on) }
    @objc private func onLabelToggled() { setPart(.label, on: labelSwitch.state == .on) }
    
    @objc private func onToggleVisibility() {
        prefs.setMetricVisible(metric, visible: enableSwitch.state == .on)
    }
    
    @objc private func positionLeft() { move(by: -1) }
    @objc private func positionRight() { move(by: 1) }
    
    private func move(by delta: Int) {
        var order = prefs.metricOrder
        guard let idx = order.firstIndex(of: metric), order.indices.contains(idx + delta) else { return }
        order.swapAt(idx, idx + delta)
        prefs.metricOrder = order
    }
    
    // MARK: - Options
    
    @objc private func onMemModeChanged() {
        switch memModePopup.indexOfSelectedItem {
        case 0: prefs.memoryDisplayMode = .percentage
        case 1: prefs.memoryDisplayMode = .usedAmount
        case 2: prefs.memoryDisplayMode = .pressure
        default: break
        }
        refresh()
    }
    
    @objc private func onTempUnitChanged() {
        guard let title = tempUnitPopup.titleOfSelectedItem, let unit = TemperatureUnit(rawValue: title) else { return }
        prefs.temperatureUnit = unit
        refresh()
    }
    
    @objc private func onApiKeyChanged() {
        prefs.weatherApiKey = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    @objc private func onCityChanged() {
        prefs.weatherCity = cityField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    @objc private func onForecastModeChanged() {
        if let mode = forecastModePopup.titleOfSelectedItem.flatMap(WeatherForecastMode.init(rawValue:)) {
            prefs.weatherForecastMode = mode
        }
    }
    
    @objc private func onWeatherIntervalChanged() {
        switch weatherIntervalPopup.indexOfSelectedItem {
        case 0: prefs.weatherUpdateInterval = 900
        case 1: prefs.weatherUpdateInterval = 1800
        default: prefs.weatherUpdateInterval = 3600
        }
    }
    
    @objc private func onTestApiKey() {
        let key = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            testStatusLabel.stringValue = "Enter your key first."
            testStatusLabel.textColor = .systemOrange
            return
        }
        prefs.weatherApiKey = key
        testStatusLabel.stringValue = "Checking…"
        testStatusLabel.textColor = .secondaryLabelColor
        testKeyButton.isEnabled = false
        
        Task { [weak self] in
            let result = await OpenWeatherMapService.shared.validateApiKey(key)
            await MainActor.run {
                guard let self else { return }
                self.testKeyButton.isEnabled = true
                switch result {
                case .success(let msg):
                    self.testStatusLabel.stringValue = "✓ \(msg)"
                    self.testStatusLabel.textColor = .systemGreen
                case .failure(let err):
                    self.testStatusLabel.stringValue = "✗ \(err.localizedDescription)"
                    self.testStatusLabel.textColor = .systemRed
                }
            }
        }
    }
    
    @objc private func openOpenWeatherMapSignup() {
        if let url = URL(string: "https://home.openweathermap.org/users/sign_up") {
            NSWorkspace.shared.open(url)
        }
    }
}
