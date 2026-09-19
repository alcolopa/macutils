import AppKit

public final class BatteryPopoverViewController: NSViewController {
    private let breakdownCard = MetricCardView(title: "Power Source", badge: "100%")
    private let batteryBar = SegmentedProgressBar(frame: .zero)
    private let stateRow = MetricRowView(label: "Source State:", color: .systemGreen)
    private let timeRow = MetricRowView(label: "Time Status:", color: .systemBlue)
    
    private let healthCard = MetricCardView(title: "Battery Health & Condition")
    private let healthRow = MetricRowView(label: "Health Condition:", color: .systemGreen)
    private let cycleRow = MetricRowView(label: "Cycle Count:", color: .secondaryLabelColor)
    
    private let scrollView = NSScrollView()
    private let container = FlippedStackView()
    
    public override func loadView() {
        let root = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 330, height: 420))
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
        
        // 1. Status Card
        batteryBar.heightAnchor.constraint(equalToConstant: 10).isActive = true
        let barContainer = NSView()
        barContainer.translatesAutoresizingMaskIntoConstraints = false
        barContainer.addSubview(batteryBar)
        batteryBar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            batteryBar.leadingAnchor.constraint(equalTo: barContainer.leadingAnchor),
            batteryBar.trailingAnchor.constraint(equalTo: barContainer.trailingAnchor),
            batteryBar.topAnchor.constraint(equalTo: barContainer.topAnchor),
            batteryBar.bottomAnchor.constraint(equalTo: barContainer.bottomAnchor)
        ])
        
        let rows = NSStackView(views: [stateRow, timeRow])
        rows.orientation = .vertical
        rows.spacing = 4
        
        let stack = NSStackView(views: [barContainer, rows])
        stack.orientation = .vertical
        stack.spacing = 8
        breakdownCard.addContentSubview(stack)
        container.addArrangedSubview(breakdownCard)
        
        // 2. Health Card
        let healthStack = NSStackView(views: [healthRow, cycleRow])
        healthStack.orientation = .vertical
        healthStack.spacing = 4
        healthCard.addContentSubview(healthStack)
        container.addArrangedSubview(healthCard)
        
        // 3. Action
        let btn = NSButton(title: "Open Battery Settings", target: self, action: #selector(openBatterySettings))
        btn.bezelStyle = .rounded
        btn.controlSize = .small
        container.addArrangedSubview(btn)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            container.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])
    }
    
    @objc private func openBatterySettings() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/Battery.prefPane"))
    }
    
    public func update(stats: BatteryStats) {
        stateRow.setValue(stats.powerSourceState)
        timeRow.setValue(stats.formattedTimeRemaining)
        
        let frac = Double(stats.currentCapacity) / 100.0
        let sev: Severity = stats.isCharging ? .normal
            : (stats.currentCapacity <= 10 ? .danger : (stats.currentCapacity <= 20 ? .warning : .normal))
        let color: NSColor = stats.isCharging ? .systemGreen : sev.color(normal: .systemBlue)
        breakdownCard.setBadge("\(stats.currentCapacity)% (\(stats.isCharging ? "Charging" : stats.powerSourceState))", tint: sev.textTint)
        batteryBar.setSegments([
            BarSegment(ratio: frac, color: color),
            BarSegment(ratio: 1.0 - frac, color: NSColor.secondaryLabelColor.withAlphaComponent(0.25))
        ])
        
        healthRow.setValue("\(stats.healthPercentage)% (\(stats.healthPercentage >= 80 ? "Normal" : "Service Recommended"))")
        cycleRow.setValue("\(stats.cycleCount) cycles")
    }
}
