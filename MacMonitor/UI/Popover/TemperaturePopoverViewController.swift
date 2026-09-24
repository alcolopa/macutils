import AppKit

public final class TemperaturePopoverViewController: NSViewController {
    private let graphView = HistoryGraphView()
    private let overviewCard = MetricCardView(title: "Overview", badge: "0°C")
    private let sensorsCard = MetricCardView(title: "Thermal Sensors Breakdown")
    private let statusCard = MetricCardView(title: "Thermal Pressure Status")
    
    private let cpuRow = MetricRowView(label: "CPU Package:", color: .systemOrange)
    private let gpuRow = MetricRowView(label: "GPU Core:", color: .systemPurple)
    private let batteryRow = MetricRowView(label: "Battery Pack:", color: .systemGreen)
    private let stateRow = MetricRowView(label: "Throttling Level:", color: .systemTeal)
    
    private let sensorsStack = NSStackView()
    
    private let scrollView = NSScrollView()
    private let container = FlippedStackView()
    
    public override func loadView() {
        let root = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 340, height: 480))
        root.material = .popover
        root.blendingMode = .behindWindow
        root.state = .active
        self.view = root
        
        setupLayout()
    }
    
    private var lastStats: TemperatureStats?
    
    public override func viewWillAppear() {
        super.viewWillAppear()
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        if let last = lastStats {
            updateVisibleDetails(stats: last)
        }
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
        
        // 1. History Graph
        let graphCard = MetricCardView(title: "Thermal History (60s)")
        graphView.heightAnchor.constraint(equalToConstant: 85).isActive = true
        graphView.series1Color = AppPreferences.shared.colorTheme.primaryColor
        graphView.maxDisplayValue = 105.0
        graphCard.addContentSubview(graphView)
        container.addArrangedSubview(graphCard)
        
        // 2. Overview Card
        let overviewStack = NSStackView(views: [cpuRow, gpuRow, batteryRow])
        overviewStack.orientation = .vertical
        overviewStack.spacing = 4
        overviewCard.addContentSubview(overviewStack)
        container.addArrangedSubview(overviewCard)
        
        // 3. Thermal State
        let statusStack = NSStackView(views: [stateRow])
        statusStack.orientation = .vertical
        statusStack.spacing = 4
        statusCard.addContentSubview(statusStack)
        container.addArrangedSubview(statusCard)
        
        // 4. Detailed Sensors List
        sensorsStack.orientation = .vertical
        sensorsStack.spacing = 4
        sensorsCard.addContentSubview(sensorsStack)
        container.addArrangedSubview(sensorsCard)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            container.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])
    }
    
    public func update(stats: TemperatureStats) {
        lastStats = stats
        let sev = Severity.level(stats.cpuTemperature, warning: 80, danger: 95)
        graphView.series1Color = sev.color(normal: AppPreferences.shared.colorTheme.primaryColor)
        graphView.push(val1: stats.cpuTemperature)
        
        guard isViewLoaded && view.window != nil else { return }
        updateVisibleDetails(stats: stats)
    }
    
    private func updateVisibleDetails(stats: TemperatureStats) {
        let isFahrenheit = AppPreferences.shared.temperatureUnit == .fahrenheit
        func formatTemp(_ celsius: Double) -> String {
            if isFahrenheit {
                return String(format: "%.1f °F", (celsius * 9.0 / 5.0 + 32.0))
            } else {
                return String(format: "%.1f °C", celsius)
            }
        }
        
        let sev = Severity.level(stats.cpuTemperature, warning: 80, danger: 95)
        overviewCard.setBadge(formatTemp(stats.cpuTemperature), tint: sev.textTint)
        
        cpuRow.setValue(formatTemp(stats.cpuTemperature), tint: sev.textTint)
        if let gpu = stats.gpuTemperature {
            gpuRow.setValue(formatTemp(gpu))
        } else {
            gpuRow.setValue("Integrated")
        }
        if let bat = stats.batteryTemperature {
            batteryRow.setValue(formatTemp(bat))
        } else {
            batteryRow.setValue("N/A")
        }
        
        stateRow.setValue(stats.thermalStateString)
        
        // Populate top distinct sensors
        sensorsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let displayedSensors = Array(stats.sensors.prefix(10))
        if displayedSensors.isEmpty {
            let label = NSTextField(labelWithString: "No hardware sensors reported")
            label.textColor = .secondaryLabelColor
            label.font = NSFont.systemFont(ofSize: 11)
            sensorsStack.addArrangedSubview(label)
        } else {
            for sensor in displayedSensors {
                let row = MetricRowView(label: "\(sensor.name):", color: colorForCategory(sensor.category))
                row.setValue(formatTemp(sensor.temperature))
                sensorsStack.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: sensorsStack.widthAnchor).isActive = true
            }
        }
    }
    
    private func colorForCategory(_ cat: SensorCategory) -> NSColor {
        switch cat {
        case .cpu: return .systemOrange
        case .gpu: return .systemPurple
        case .battery: return .systemGreen
        case .system: return .systemTeal
        }
    }
}
