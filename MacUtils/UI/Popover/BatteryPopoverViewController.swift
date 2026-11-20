import AppKit

public final class BatteryPopoverViewController: NSViewController {
    private let graphView = HistoryGraphView()
    private let overviewCard = MetricCardView(title: "Battery Status", badge: "100%")
    private let powerCard = MetricCardView(title: "Power & Adapter")
    private let healthCard = MetricCardView(title: "Health & Capacity")
    
    private let stateRow = MetricRowView(label: "State:", color: .systemGreen)
    private let timeRow = MetricRowView(label: "Time Remaining:", color: .systemBlue)
    private let conditionRow = MetricRowView(label: "Condition:", color: .systemTeal)
    
    private let sourceRow = MetricRowView(label: "Power Source:", color: .systemOrange)
    private let wattageRow = MetricRowView(label: "Live Wattage:", color: .systemYellow)
    private let voltageRow = MetricRowView(label: "Voltage:", color: .systemPurple)
    private let amperageRow = MetricRowView(label: "Amperage:", color: .systemIndigo)
    
    private let healthRow = MetricRowView(label: "Maximum Capacity:", color: .systemGreen)
    private let cycleRow = MetricRowView(label: "Cycle Count:", color: .systemCyan)
    private let capacityRow = MetricRowView(label: "Raw Capacity:", color: .secondaryLabelColor)
    
    private let levelBar = SegmentedProgressBar(frame: .zero)
    private let scrollView = NSScrollView()
    private let container = FlippedStackView()
    private var lastStats: BatteryStats?
    
    public override func loadView() {
        let root = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 340, height: 490))
        root.material = .popover
        root.blendingMode = .behindWindow
        root.state = .active
        self.view = root
        
        setupLayout()
    }
    
    public override func viewWillAppear() {
        super.viewWillAppear()
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        if let last = lastStats {
            updateVisibleDetails(stats: last)
        }
    }
    
    public func update(stats: BatteryStats) {
        lastStats = stats
        let theme = AppPreferences.shared.colorTheme
        let color: NSColor = stats.percentage <= 20.0 ? .systemRed : (stats.isCharging ? .systemGreen : theme.primaryColor)
        graphView.series1Color = color
        graphView.push(val1: stats.percentage)
        
        guard isViewLoaded && view.window != nil else { return }
        updateVisibleDetails(stats: stats)
    }
    
    private func updateVisibleDetails(stats: BatteryStats) {
        overviewCard.setBadge(stats.formattedPercentage, tint: stats.percentage <= 20.0 ? .systemRed : (stats.isCharging ? .systemGreen : .labelColor))
        
        let stateStr = stats.isCharging ? "Charging" : (stats.isPluggedIn ? "AC Connected (Not Charging)" : "Discharging (On Battery)")
        stateRow.setValue(stateStr)
        timeRow.setValue(stats.formattedTimeRemaining)
        conditionRow.setValue(stats.condition)
        
        sourceRow.setValue(stats.powerSourceState)
        wattageRow.setValue(stats.formattedWattage)
        if let v = stats.voltageMilliVolts {
            voltageRow.setValue(String(format: "%.2f V", Double(v) / 1000.0))
        } else {
            voltageRow.setValue("-- V")
        }
        if let a = stats.amperageMilliAmps {
            amperageRow.setValue(String(format: "%d mA", a))
        } else {
            amperageRow.setValue("-- mA")
        }
        
        if let h = stats.healthPercentage {
            healthRow.setValue(String(format: "%.1f%%", h))
        } else {
            healthRow.setValue("Normal")
        }
        if let c = stats.cycleCount {
            cycleRow.setValue("\(c)")
        } else {
            cycleRow.setValue("--")
        }
        if let m = stats.maxCapacityMAh {
            capacityRow.setValue("\(m) mAh")
        } else {
            capacityRow.setValue("--")
        }
        
        let ratio = max(0.0, min(stats.percentage / 100.0, 1.0))
        let theme = AppPreferences.shared.colorTheme
        levelBar.setSegments([
            BarSegment(ratio: ratio, color: stats.percentage <= 20.0 ? .systemRed : (stats.isCharging ? .systemGreen : theme.primaryColor))
        ])
    }
    
    private func setupLayout() {
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
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
        
        // 1. Graph Section
        let theme = AppPreferences.shared.colorTheme
        let graphCard = MetricCardView(title: "Battery Level History (60s)")
        graphView.heightAnchor.constraint(equalToConstant: 80).isActive = true
        graphView.series1Color = theme.primaryColor
        graphCard.addContentSubview(graphView)
        container.addArrangedSubview(graphCard)
        
        // 2. Overview Card
        levelBar.heightAnchor.constraint(equalToConstant: 8).isActive = true
        let overviewStack = NSStackView(views: [levelBar, stateRow, timeRow, conditionRow])
        overviewStack.orientation = .vertical
        overviewStack.spacing = 4
        overviewCard.addContentSubview(overviewStack)
        container.addArrangedSubview(overviewCard)
        
        // 3. Power & Adapter Card
        let powerStack = NSStackView(views: [sourceRow, wattageRow, voltageRow, amperageRow])
        powerStack.orientation = .vertical
        powerStack.spacing = 4
        powerCard.addContentSubview(powerStack)
        container.addArrangedSubview(powerCard)
        
        // 4. Health Card
        let healthStack = NSStackView(views: [healthRow, cycleRow, capacityRow])
        healthStack.orientation = .vertical
        healthStack.spacing = 4
        healthCard.addContentSubview(healthStack)
        container.addArrangedSubview(healthCard)
        
        // 5. Open Battery Settings
        let sysSettingsBtn = NSButton(title: "Open Battery Settings...", target: self, action: #selector(openBatterySettings))
        sysSettingsBtn.bezelStyle = .rounded
        sysSettingsBtn.controlSize = .small
        container.addArrangedSubview(sysSettingsBtn)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            container.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])
    }
    
    @objc private func openBatterySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.battery") {
            NSWorkspace.shared.open(url)
        }
    }
}
