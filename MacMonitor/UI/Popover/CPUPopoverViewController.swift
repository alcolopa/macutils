import AppKit

public final class CPUPopoverViewController: NSViewController {
    private let graphView = HistoryGraphView()
    private let breakdownCard = MetricCardView(title: "Overview", badge: "0%")
    private let systemInfoCard = MetricCardView(title: "System & Thermal State")
    private let topProcCard = MetricCardView(title: "Top Processes by CPU", contentInsets: NSEdgeInsets(top: 8, left: 6, bottom: 8, right: 6))
    private let procTableView = ProcessTableView(mode: .cpu)
    private let coresCard = MetricCardView(title: "Per-Core Load")
    
    private let userRow = MetricRowView(label: "User:", color: .systemBlue)
    private let sysRow = MetricRowView(label: "System:", color: .systemTeal)
    private let idleRow = MetricRowView(label: "Idle:", color: .secondaryLabelColor)
    
    private let modelRow = MetricRowView(label: "CPU Model:", color: .systemPurple)
    private let thermalRow = MetricRowView(label: "Thermal State:", color: .systemGreen)
    private let loadRow = MetricRowView(label: "Load Avg (1/5/15m):", color: .systemOrange)
    private let uptimeRow = MetricRowView(label: "System Uptime:", color: .systemGreen)
    
    private let coresStack = NSStackView()
    private var coreBarViews: [CoreMiniBarView] = []
    
    private let scrollView = NSScrollView()
    private let container = FlippedStackView()
    
    public override func loadView() {
        let root = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 340, height: 530))
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
        
        // 1. Graph Section
        let theme = AppPreferences.shared.colorTheme
        let graphCard = MetricCardView(title: "CPU History (60s)")
        graphView.heightAnchor.constraint(equalToConstant: 85).isActive = true
        graphView.series1Color = theme.primaryColor
        graphCard.addContentSubview(graphView)
        container.addArrangedSubview(graphCard)
        
        // 2. Overview Card
        let overviewStack = NSStackView(views: [userRow, sysRow, idleRow])
        overviewStack.orientation = .vertical
        overviewStack.spacing = 4
        breakdownCard.addContentSubview(overviewStack)
        container.addArrangedSubview(breakdownCard)
        
        // 3. System Info Card (Load Average & Uptime & Thermal)
        let sysInfoStack = NSStackView(views: [modelRow, thermalRow, loadRow, uptimeRow])
        sysInfoStack.orientation = .vertical
        sysInfoStack.spacing = 4
        systemInfoCard.addContentSubview(sysInfoStack)
        container.addArrangedSubview(systemInfoCard)
        
        // 4. Top Processes Card with App Icons
        topProcCard.addContentSubview(procTableView)
        container.addArrangedSubview(topProcCard)
        
        // 5. Cores Grid Card
        coresStack.orientation = .vertical
        coresStack.spacing = 4
        coresCard.addContentSubview(coresStack)
        container.addArrangedSubview(coresCard)
        
        // 6. Action Footer
        let activityMonitorBtn = NSButton(title: "Open Activity Monitor", target: self, action: #selector(openActivityMonitor))
        activityMonitorBtn.bezelStyle = .rounded
        activityMonitorBtn.controlSize = .small
        container.addArrangedSubview(activityMonitorBtn)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            container.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            topProcCard.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -28)
        ])
    }
    
    @objc private func openActivityMonitor() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
    }
    
    public func update(stats: CPUStats) {
        let theme = AppPreferences.shared.colorTheme
        graphView.series1Color = theme.primaryColor
        graphView.push(val1: stats.totalUsage)
        breakdownCard.setBadge(String(format: "%.1f%%", stats.totalUsage))
        
        let loads = stats.perCoreLoads
        if !loads.isEmpty {
            let avgUser = loads.reduce(0.0) { $0 + $1.userPercentage } / Double(loads.count)
            let avgSys = loads.reduce(0.0) { $0 + $1.systemPercentage } / Double(loads.count)
            let avgIdle = loads.reduce(0.0) { $0 + $1.idlePercentage } / Double(loads.count)
            
            userRow.setValue(String(format: "%.1f%%", avgUser))
            sysRow.setValue(String(format: "%.1f%%", avgSys))
            idleRow.setValue(String(format: "%.1f%%", avgIdle))
        }
        
        modelRow.setValue(stats.cpuModel)
        
        // Thermal State
        let thermal = ProcessInfo.processInfo.thermalState
        let thermalStr: String
        switch thermal {
        case .nominal:  thermalStr = "Nominal (Cool)"
        case .fair:     thermalStr = "Fair (Warm)"
        case .serious:  thermalStr = "Serious (Throttling)"
        case .critical: thermalStr = "Critical (High Heat)"
        @unknown default: thermalStr = "Normal"
        }
        thermalRow.setValue(thermalStr)
        
        let la = stats.loadAverages
        loadRow.setValue(String(format: "%.2f, %.2f, %.2f", la[0], la[1], la[2]))
        uptimeRow.setValue(stats.formattedUptime)
        
        // Update top processes table with icons
        procTableView.update(processes: stats.topProcesses)
        
        // Cores
        if coreBarViews.count != loads.count {
            coresStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
            coreBarViews.removeAll()
            
            for load in loads {
                let bar = CoreMiniBarView(coreIndex: load.coreIndex)
                coreBarViews.append(bar)
                coresStack.addArrangedSubview(bar)
                bar.widthAnchor.constraint(equalTo: coresStack.widthAnchor).isActive = true
            }
        }
        
        for (i, load) in loads.enumerated() {
            if i < coreBarViews.count {
                coreBarViews[i].update(load: load)
            }
        }
    }
}

final class CoreMiniBarView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private let bar = SegmentedProgressBar(frame: .zero)
    
    init(coreIndex: Int) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 14).isActive = true
        
        label.stringValue = "Core \(coreIndex + 1)"
        label.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        label.textColor = NSColor.secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        
        bar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bar)
        
        valueLabel.stringValue = "0%"
        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        valueLabel.alignment = .right
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(valueLabel)
        
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.widthAnchor.constraint(equalToConstant: 45),
            
            bar.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 4),
            bar.centerYAnchor.constraint(equalTo: centerYAnchor),
            bar.heightAnchor.constraint(equalToConstant: 6),
            bar.trailingAnchor.constraint(equalTo: valueLabel.leadingAnchor, constant: -6),
            
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueLabel.widthAnchor.constraint(equalToConstant: 32)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }
    
    func update(load: CoreLoad) {
        valueLabel.stringValue = String(format: "%.0f%%", load.totalUsagePercentage)
        let userR = load.userPercentage / 100.0
        let sysR = load.systemPercentage / 100.0
        let theme = AppPreferences.shared.colorTheme
        bar.setSegments([
            BarSegment(ratio: userR, color: theme.primaryColor),
            BarSegment(ratio: sysR, color: theme.secondaryColor)
        ])
    }
}
