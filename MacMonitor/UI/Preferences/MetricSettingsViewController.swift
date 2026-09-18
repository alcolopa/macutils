import AppKit

public final class MetricSettingsViewController: NSViewController, WidgetStylePickerViewDelegate, SingleMetricWidgetPreviewDelegate {
    private let metric: MetricType
    private let prefs = AppPreferences.shared
    
    private let livePreview: MenuBarLivePreviewView
    private let widgetPreview: SingleMetricWidgetPreviewView
    private let stylePicker: WidgetStylePickerView
    
    private let enableCheck = NSButton(checkboxWithTitle: "Enable status bar item", target: nil, action: nil)
    private let displayStylePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    
    // Menu bar appearance controls
    private let iconCheck = NSButton()
    private let labelCheck = NSButton()
    private let iconPositionPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let iconSizePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let iconTintPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let paddingSlider = NSSlider(value: 0, minValue: 0, maxValue: 12, target: nil, action: nil)
    private let paddingValueLabel = NSTextField(labelWithString: "0 pt")
    
    // Module specific controls
    private let memModePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let tempUnitPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    
    // Weather specific controls
    private let apiKeyField = NSSecureTextField()
    private let cityField = NSTextField()
    private let weatherIntervalPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let testKeyButton = NSButton(title: "Test Connection", target: nil, action: nil)
    private let testStatusLabel = NSTextField(labelWithString: "")
    
    public init(metric: MetricType) {
        self.metric = metric
        self.livePreview = MenuBarLivePreviewView(focusedMetric: metric)
        self.widgetPreview = SingleMetricWidgetPreviewView(metric: metric)
        self.stylePicker = WidgetStylePickerView(metric: metric)
        super.init(nibName: nil, bundle: nil)
        self.title = metric.displayName
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func loadView() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 620, height: 500))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        
        let contentView = FlippedView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        
        let clipView = NSClipView()
        clipView.drawsBackground = false
        clipView.documentView = contentView
        scrollView.contentView = clipView
        
        self.view = scrollView
        
        setupUI(in: contentView, parentScrollView: scrollView)
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        widgetPreview.delegate = self
        stylePicker.delegate = self
    }
    
    private func setupUI(in container: NSView, parentScrollView: NSScrollView) {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 24
        stack.edgeInsets = NSEdgeInsets(top: 28, left: 32, bottom: 36, right: 32)
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        
        // 1. Preview + style picker
        stack.addArrangedSubview(SettingsLayout.card(title: "\(metric.displayName) Preview", [
            widgetPreview,
            SettingsLayout.paragraph("Pick a style below (click, or drag it onto the preview).", small: true),
            stylePicker
        ]))
        
        // 3. Basic settings
        enableCheck.title = "Show in menu bar"
        enableCheck.state = prefs.isMetricVisible(metric) ? .on : .off
        enableCheck.target = self
        enableCheck.action = #selector(onToggleVisibility)
        
        let availableStyles = AppPreferences.availableStyles(for: metric)
        displayStylePopup.removeAllItems()
        for style in availableStyles { displayStylePopup.addItem(withTitle: style.displayName) }
        displayStylePopup.selectItem(withTitle: prefs.displayStyle(for: metric).displayName)
        displayStylePopup.target = self
        displayStylePopup.action = #selector(onDisplayStyleChanged)
        
        stack.addArrangedSubview(SettingsLayout.card(title: "Widget", [
            SettingsLayout.row("Visibility", enableCheck),
            SettingsLayout.row("Style", displayStylePopup)
        ]))
        
        // 4. Appearance customisation (icon, label, padding)
        let opts = prefs.barOptions(for: metric)
        iconCheck.state = opts.showIcon ? .on : .off
        labelCheck.state = opts.showLabel ? .on : .off
        configureChip(iconCheck, title: "Icon", symbol: metric.iconSymbolName)
        configureChip(labelCheck, title: "Label", symbol: "textformat")
        let chipRow = NSStackView(views: [iconCheck, labelCheck])
        chipRow.orientation = .horizontal
        chipRow.spacing = 10
        chipRow.distribution = .fillEqually
        
        iconPositionPopup.removeAllItems()
        iconPositionPopup.addItems(withTitles: BarIconPosition.allCases.map { $0.rawValue })
        iconPositionPopup.selectItem(withTitle: opts.iconPosition.rawValue)
        iconSizePopup.removeAllItems()
        iconSizePopup.addItems(withTitles: BarIconSize.allCases.map { $0.rawValue })
        iconSizePopup.selectItem(withTitle: opts.iconSize.rawValue)
        iconTintPopup.removeAllItems()
        iconTintPopup.addItems(withTitles: BarIconTint.allCases.map { $0.rawValue })
        iconTintPopup.selectItem(withTitle: opts.iconTint.rawValue)
        for pop in [iconPositionPopup, iconSizePopup, iconTintPopup] { pop.target = self; pop.action = #selector(onBarOptionChanged) }
        
        paddingSlider.minValue = 0
        paddingSlider.maxValue = 12
        paddingSlider.doubleValue = opts.padding
        paddingSlider.target = self
        paddingSlider.action = #selector(onBarOptionChanged)
        paddingValueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        paddingValueLabel.stringValue = "\(Int(opts.padding)) pt"
        paddingValueLabel.translatesAutoresizingMaskIntoConstraints = false
        paddingValueLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true
        
        var appearanceRows: [NSView] = []
        if metric == .weather {
            appearanceRows.append(SettingsLayout.paragraph("The weather widget already shows a live condition icon, so an extra icon is off by default.", small: true))
        }
        appearanceRows += [
            SettingsLayout.paragraph("Click a box to turn that part of the widget on or off."),
            chipRow,
            SettingsLayout.row("Icon position", iconPositionPopup),
            SettingsLayout.row("Icon size", iconSizePopup),
            SettingsLayout.row("Icon colour", iconTintPopup),
            SettingsLayout.row("Padding", paddingSlider, trailing: paddingValueLabel)
        ]
        stack.addArrangedSubview(SettingsLayout.card(title: "Menu Bar Appearance", appearanceRows))
        
        // 5. Module-specific options + about text
        let moduleRows = NSStackView()
        moduleRows.orientation = .vertical
        moduleRows.alignment = .leading
        moduleRows.spacing = 16
        moduleRows.translatesAutoresizingMaskIntoConstraints = false
        
        switch metric {
        case .cpu:
            let p1 = SettingsLayout.paragraph(
                "CPU Activity provides real-time telemetry into Apple Silicon and Intel processor utilization. " +
                "The engine samples per-core Mach ticks directly from the Darwin kernel to accurately capture User, System, " +
                "and Idle workloads, as well as 1-minute, 5-minute, and 15-minute system load averages."
            )
            let p2 = SettingsLayout.paragraph(
                "Customization options:\n" +
                "• Bar Only: Compact miniature load activity bars with zero clutter.\n" +
                "• Standard: Clean percentage readout paired with a 5-sample live sparkline.\n" +
                "• Circular Gauge: Minimalist circular ring reflecting overall processor load.\n" +
                "• Text Only: Clean, legible percentage with lowest menubar footprint."
            )
            moduleRows.addArrangedSubview(p1)
            
        case .memory:
            let memFormatTitle = NSTextField(labelWithString: "Text Display Format:")
            memFormatTitle.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            
            memModePopup.removeAllItems()
            memModePopup.addItems(withTitles: ["Percentage (%)", "Used Amount (GB)", "Memory Pressure (NORM/WARN/CRIT)"])
            switch prefs.memoryDisplayMode {
            case .percentage: memModePopup.selectItem(at: 0)
            case .usedAmount: memModePopup.selectItem(at: 1)
            case .pressure:   memModePopup.selectItem(at: 2)
            }
            memModePopup.target = self
            memModePopup.action = #selector(onMemModeChanged)
            
            let row = NSStackView(views: [memFormatTitle, memModePopup])
            row.orientation = .horizontal
            row.spacing = 10
            moduleRows.addArrangedSubview(row)
            
            let p1 = SettingsLayout.paragraph(
                "Memory & Swap tracks macOS unified memory allocation in real time using Mach host statistics. " +
                "Rather than merely displaying free RAM (which macOS intentionally fills with file caches), MacMonitor separates " +
                "active application memory, wired OS kernel pages, and compressed memory segments."
            )
            let p2 = SettingsLayout.paragraph(
                "Customization options:\n" +
                "• Multicoloured Circle: An elegant segmented donut chart showing App, Wired, and Compressed allocations.\n" +
                "• Standard: Percentage readout with a vertical miniature memory meter.\n" +
                "• Bar Only: Single capsule bar tracking overall allocation.\n" +
                "• Circular Gauge: Smooth single-color ring gauge.\n" +
                "• Text Only: Direct numeric value or memory pressure level."
            )
            moduleRows.addArrangedSubview(p1)
            
        case .temperatures:
            let tempUnitTitle = NSTextField(labelWithString: "Temperature Unit:")
            tempUnitTitle.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            
            tempUnitPopup.removeAllItems()
            for unit in TemperatureUnit.allCases {
                tempUnitPopup.addItem(withTitle: unit.rawValue)
            }
            tempUnitPopup.selectItem(withTitle: prefs.temperatureUnit.rawValue)
            tempUnitPopup.target = self
            tempUnitPopup.action = #selector(onTempUnitChanged)
            
            let row = NSStackView(views: [tempUnitTitle, tempUnitPopup])
            row.orientation = .horizontal
            row.spacing = 10
            moduleRows.addArrangedSubview(row)
            
            let p1 = SettingsLayout.paragraph(
                "Temperatures & Sensors reads on-die thermal sensors via Apple System Management Controller (SMC) and " +
                "Apple Silicon HID event services. Monitored thermal zones include CPU performance and efficiency cores, " +
                "integrated GPU clusters, NAND flash storage controllers, and battery thermal packs."
            )
            let p2 = SettingsLayout.paragraph(
                "Customization options:\n" +
                "• Standard: Live degree readout with thermal glyph indicator.\n" +
                "• Circular Gauge: Circular heat ring scaled between normal and peak operating temperatures.\n" +
                "• Text Only: Minimal temperature readout."
            )
            moduleRows.addArrangedSubview(p1)
            
        case .displays:
            let p1 = SettingsLayout.paragraph(
                "Displays & Monitors inspects active monitor connections, native pixel resolutions, high refresh rates " +
                "(including Apple 120Hz ProMotion), retina scaling configurations, and color profiles via Quartz Display Services."
            )
            let openSysDisplays = NSButton(title: "Open macOS Displays Settings...", target: self, action: #selector(openDisplaySettings))
            openSysDisplays.bezelStyle = .rounded
            openSysDisplays.controlSize = .small
            
            moduleRows.addArrangedSubview(p1)
            moduleRows.addArrangedSubview(openSysDisplays)
            
        case .disk:
            let p1 = SettingsLayout.paragraph(
                "Disk Storage inspects root APFS container volumes, tracking total allocated space, system snapshots, " +
                "purgeable cache allocations, and real-time read/write I/O throughput across active solid-state storage."
            )
            let p2 = SettingsLayout.paragraph(
                "Customization options:\n" +
                "• Bar Only: Horizontal storage usage capsule bar.\n" +
                "• Circular Gauge: Circular gauge showing disk capacity percentage.\n" +
                "• Standard: Percentage readout with miniature capacity meter.\n" +
                "• Text Only: Clean percentage text."
            )
            moduleRows.addArrangedSubview(p1)
            
        case .network:
            let p1 = SettingsLayout.paragraph(
                "Network Activity monitors real-time upload and download bandwidth across active network interfaces " +
                "(Wi-Fi, Ethernet, and Thunderbolt bridges) using Darwin routing sockets."
            )
            let p2 = SettingsLayout.paragraph(
                "Customization options:\n" +
                "• Standard: Dual-row upload (⇡) and download (⇣) speeds in dynamic K/s and M/s.\n" +
                "• Text Only: Combined total throughput in a single line."
            )
            moduleRows.addArrangedSubview(p1)
            
        case .battery:
            let p1 = SettingsLayout.paragraph(
                "Battery & Power interfaces directly with Apple Smart Battery IOKit registries, querying live battery charge, " +
                "maximum design health capacity, AC adapter wattage, current cycle count, and remaining runtime or charge completion time."
            )
            let p2 = SettingsLayout.paragraph(
                "Customization options:\n" +
                "• Standard: Numerical percentage accompanied by a responsive battery icon with fill level and charging indicator.\n" +
                "• Bar Only: Battery icon glyph only.\n" +
                "• Text Only: Numerical percentage only."
            )
            moduleRows.addArrangedSubview(p1)
            
        case .weather:
            // 1. API Key Input Row
            let keyLabel = NSTextField(labelWithString: "OpenWeatherMap API Key:")
            keyLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            
            apiKeyField.placeholderString = "Paste 32-character API key here"
            apiKeyField.stringValue = prefs.weatherApiKey
            apiKeyField.target = self
            apiKeyField.action = #selector(onApiKeyChanged)
            apiKeyField.translatesAutoresizingMaskIntoConstraints = false
            apiKeyField.widthAnchor.constraint(equalToConstant: 240).isActive = true
            
            let getKeyBtn = NSButton(title: "Get Free Key ↗", target: self, action: #selector(openOpenWeatherMapSignup))
            getKeyBtn.bezelStyle = .inline
            getKeyBtn.controlSize = .small
            
            let keyRow = NSStackView(views: [keyLabel, apiKeyField, getKeyBtn])
            keyRow.orientation = .horizontal
            keyRow.spacing = 8
            keyRow.alignment = .centerY
            moduleRows.addArrangedSubview(keyRow)
            
            // 2. Test Connection Button & Status
            testKeyButton.bezelStyle = .rounded
            testKeyButton.controlSize = .small
            testKeyButton.target = self
            testKeyButton.action = #selector(onTestApiKey)
            
            testStatusLabel.font = NSFont.systemFont(ofSize: 11)
            testStatusLabel.textColor = .secondaryLabelColor
            
            let testRow = NSStackView(views: [testKeyButton, testStatusLabel])
            testRow.orientation = .horizontal
            testRow.spacing = 8
            testRow.alignment = .centerY
            moduleRows.addArrangedSubview(testRow)
            
            // 3. Location / City Input Row
            let cityLabel = NSTextField(labelWithString: "Location / City:")
            cityLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            
            cityField.placeholderString = "e.g. London, UK or 'auto'"
            cityField.stringValue = prefs.weatherCity
            cityField.target = self
            cityField.action = #selector(onCityChanged)
            cityField.translatesAutoresizingMaskIntoConstraints = false
            cityField.widthAnchor.constraint(equalToConstant: 200).isActive = true
            
            let autoHint = NSTextField(labelWithString: "(Enter city name, or 'auto' for automatic location)")
            autoHint.font = NSFont.systemFont(ofSize: 11)
            autoHint.textColor = .tertiaryLabelColor
            
            let cityRow = NSStackView(views: [cityLabel, cityField, autoHint])
            cityRow.orientation = .horizontal
            cityRow.spacing = 8
            cityRow.alignment = .centerY
            moduleRows.addArrangedSubview(cityRow)
            
            // 4. Update Interval Popup
            let intervalTitle = NSTextField(labelWithString: "Refresh Interval:")
            intervalTitle.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            
            weatherIntervalPopup.removeAllItems()
            weatherIntervalPopup.addItems(withTitles: ["Every 15 Minutes", "Every 30 Minutes", "Every 1 Hour"])
            let currentSec = prefs.weatherUpdateInterval
            if currentSec <= 900 {
                weatherIntervalPopup.selectItem(at: 0)
            } else if currentSec <= 1800 {
                weatherIntervalPopup.selectItem(at: 1)
            } else {
                weatherIntervalPopup.selectItem(at: 2)
            }
            weatherIntervalPopup.target = self
            weatherIntervalPopup.action = #selector(onWeatherIntervalChanged)
            
            let intervalRow = NSStackView(views: [intervalTitle, weatherIntervalPopup])
            intervalRow.orientation = .horizontal
            intervalRow.spacing = 8
            moduleRows.addArrangedSubview(intervalRow)
            
            let p1 = SettingsLayout.paragraph(
                "OpenWeatherMap provides high-resolution global weather telemetry. " +
                "You can obtain a completely free API key by registering at openweathermap.org. " +
                "The free plan includes 1,000 API calls per day, which comfortably supports updates every 15-30 minutes."
            )
            let p2 = SettingsLayout.paragraph(
                "Customization options:\n" +
                "• Standard: Current temperature alongside dynamic weather glyph (e.g. ⛅ 21°C).\n" +
                "• Text Only: Numerical temperature with current unit format (e.g. 21°C or 70°F).\n" +
                "• Bar Only: Minimalist weather condition icon only.\n" +
                "• Circular Gauge: Circular ring indicating ambient temperature comfort index."
            )
            moduleRows.addArrangedSubview(p1)
        }
        
        
        stack.addArrangedSubview(SettingsLayout.card(title: metric == .weather ? "Weather Service" : "About", [moduleRows]))
        
        // Critical auto-layout fix: constrain content width to scroll view width so text wraps cleanly
        // Every card spans the full page width (minus side insets) so edges line up
        for card in stack.arrangedSubviews {
            card.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -(stack.edgeInsets.left + stack.edgeInsets.right)).isActive = true
        }
        
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            
            container.topAnchor.constraint(equalTo: parentScrollView.topAnchor),
            container.leadingAnchor.constraint(equalTo: parentScrollView.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: parentScrollView.trailingAnchor),
            container.widthAnchor.constraint(equalTo: parentScrollView.widthAnchor)
        ])
    }
    
    private func createParagraph(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = NSColor.secondaryLabelColor
        label.lineBreakMode = .byWordWrapping
        label.isSelectable = true
        label.maximumNumberOfLines = 0
        label.preferredMaxLayoutWidth = 550
        return label
    }
    
    private func createSeparator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return box
    }
    
    // MARK: - WidgetStylePickerViewDelegate & Drop
    
    public func widgetStylePickerView(_ picker: WidgetStylePickerView, didSelectStyle style: MetricDisplayStyle) {
        applyStyle(style)
    }
    
    public func singleMetricWidgetPreview(_ preview: SingleMetricWidgetPreviewView, didDropStyle style: MetricDisplayStyle) {
        applyStyle(style)
    }
    
    private func applyStyle(_ style: MetricDisplayStyle) {
        prefs.setDisplayStyle(style, for: metric)
        displayStylePopup.selectItem(withTitle: style.displayName)
        widgetPreview.refreshPreview()
        stylePicker.refreshStyles()
        livePreview.refreshPreview()
    }
    
    public func singleMetricWidgetPreviewDidRequestMoveLeft(_ preview: SingleMetricWidgetPreviewView) {
        var order = prefs.metricOrder
        guard let idx = order.firstIndex(of: metric), idx > 0 else { return }
        order.swapAt(idx, idx - 1)
        prefs.metricOrder = order
        widgetPreview.refreshPreview()
        livePreview.refreshPreview()
    }
    
    public func singleMetricWidgetPreviewDidRequestMoveRight(_ preview: SingleMetricWidgetPreviewView) {
        var order = prefs.metricOrder
        guard let idx = order.firstIndex(of: metric), idx < order.count - 1 else { return }
        order.swapAt(idx, idx + 1)
        prefs.metricOrder = order
        widgetPreview.refreshPreview()
        livePreview.refreshPreview()
    }
    
    private func configureChip(_ b: NSButton, title: String, symbol: String) {
        b.setButtonType(.pushOnPushOff)
        b.bezelStyle = .rounded
        b.title = title
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        b.imagePosition = .imageLeading
        b.controlSize = .large
        b.translatesAutoresizingMaskIntoConstraints = false
        b.heightAnchor.constraint(equalToConstant: 44).isActive = true
        b.target = self
        b.action = #selector(onBarOptionChanged)
        updateChip(b)
    }
    
    private func updateChip(_ b: NSButton) {
        b.bezelColor = b.state == .on ? .controlAccentColor : nil
        b.contentTintColor = b.state == .on ? .white : .secondaryLabelColor
    }
    
    @objc private func onBarOptionChanged() {
        updateChip(iconCheck)
        updateChip(labelCheck)
        var o = prefs.barOptions(for: metric)
        o.showIcon = iconCheck.state == .on
        o.showLabel = labelCheck.state == .on
        o.iconPosition = iconPositionPopup.titleOfSelectedItem.flatMap(BarIconPosition.init(rawValue:)) ?? o.iconPosition
        o.iconSize = iconSizePopup.titleOfSelectedItem.flatMap(BarIconSize.init(rawValue:)) ?? o.iconSize
        o.iconTint = iconTintPopup.titleOfSelectedItem.flatMap(BarIconTint.init(rawValue:)) ?? o.iconTint
        o.padding = round(paddingSlider.doubleValue)
        paddingValueLabel.stringValue = "\(Int(o.padding)) pt"
        prefs.setBarOptions(o, for: metric)
        livePreview.refreshPreview()
    }
    
    @objc private func onToggleVisibility() {
        prefs.setMetricVisible(metric, visible: enableCheck.state == .on)
        livePreview.refreshPreview()
    }
    
    @objc private func onDisplayStyleChanged() {
        guard let title = displayStylePopup.titleOfSelectedItem else { return }
        let available = AppPreferences.availableStyles(for: metric)
        if let match = available.first(where: { $0.displayName == title }) {
            applyStyle(match)
        }
    }
    
    @objc private func onMemModeChanged() {
        switch memModePopup.indexOfSelectedItem {
        case 0: prefs.memoryDisplayMode = .percentage
        case 1: prefs.memoryDisplayMode = .usedAmount
        case 2: prefs.memoryDisplayMode = .pressure
        default: break
        }
        widgetPreview.refreshPreview()
        stylePicker.refreshStyles()
        livePreview.refreshPreview()
    }
    
    @objc private func onTempUnitChanged() {
        guard let title = tempUnitPopup.titleOfSelectedItem,
              let unit = TemperatureUnit(rawValue: title) else { return }
        prefs.temperatureUnit = unit
        widgetPreview.refreshPreview()
        stylePicker.refreshStyles()
        livePreview.refreshPreview()
    }
    
    @objc private func openDisplaySettings() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/Displays.prefPane"))
    }
    
    // MARK: - Weather Action Handlers
    
    @objc private func onApiKeyChanged() {
        prefs.weatherApiKey = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    @objc private func onCityChanged() {
        prefs.weatherCity = cityField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    @objc private func onWeatherIntervalChanged() {
        switch weatherIntervalPopup.indexOfSelectedItem {
        case 0: prefs.weatherUpdateInterval = 900   // 15 mins
        case 1: prefs.weatherUpdateInterval = 1800  // 30 mins
        case 2: prefs.weatherUpdateInterval = 3600  // 1 hour
        default: prefs.weatherUpdateInterval = 1800
        }
    }
    
    @objc private func onTestApiKey() {
        let key = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            testStatusLabel.stringValue = "⚠️ Please enter an API key first."
            testStatusLabel.textColor = .systemOrange
            return
        }
        
        prefs.weatherApiKey = key
        testStatusLabel.stringValue = "Connecting to OpenWeatherMap..."
        testStatusLabel.textColor = .secondaryLabelColor
        testKeyButton.isEnabled = false
        
        Task { [weak self] in
            let result = await OpenWeatherMapService.shared.validateApiKey(key)
            await MainActor.run {
                guard let self = self else { return }
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
