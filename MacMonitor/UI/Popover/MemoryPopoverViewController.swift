import AppKit

public final class MemoryPopoverViewController: NSViewController {
    private let graphView = HistoryGraphView()
    private let pressureCard = MetricCardView(title: "Memory Pressure", badge: "Normal")
    private let ramCard = MetricCardView(title: "Memory Breakdown", badge: "0%")
    private let swapCard = MetricCardView(title: "Swap Space", badge: "0 MB")
    private let topProcCard = MetricCardView(title: "Top Processes by RAM")
    private let procTableView = ProcessTableView(mode: .memory)
    
    private let pressureBar = SegmentedProgressBar(frame: .zero)
    private let pressureStatusRow = MetricRowView(label: "Pressure Status:", color: .systemGreen)
    
    private let ramBar = SegmentedProgressBar(frame: .zero)
    private let appRow = MetricRowView(label: "App Memory:", color: .systemBlue)
    private let wiredRow = MetricRowView(label: "Wired Memory:", color: .systemIndigo)
    private let compressedRow = MetricRowView(label: "Compressed:", color: .systemTeal)
    private let freeRow = MetricRowView(label: "Free Memory:", color: .systemGreen)
    
    private let swapBar = SegmentedProgressBar(frame: .zero)
    private let swapUsedRow = MetricRowView(label: "Swap Used:", color: .systemOrange)
    private let swapFreeRow = MetricRowView(label: "Swap Free:", color: .secondaryLabelColor)
    
    private let scrollView = NSScrollView()
    private let container = FlippedStackView()
    
    public override func loadView() {
        let root = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 340, height: 550))
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
        let graphCard = MetricCardView(title: "Memory History (60s)")
        graphView.heightAnchor.constraint(equalToConstant: 85).isActive = true
        graphView.series1Color = theme.secondaryColor
        graphCard.addContentSubview(graphView)
        container.addArrangedSubview(graphCard)
        
        // 2. Memory Pressure Card
        pressureBar.heightAnchor.constraint(equalToConstant: 8).isActive = true
        let pBarCont = NSView()
        pBarCont.translatesAutoresizingMaskIntoConstraints = false
        pBarCont.addSubview(pressureBar)
        pressureBar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pressureBar.leadingAnchor.constraint(equalTo: pBarCont.leadingAnchor),
            pressureBar.trailingAnchor.constraint(equalTo: pBarCont.trailingAnchor),
            pressureBar.topAnchor.constraint(equalTo: pBarCont.topAnchor),
            pressureBar.bottomAnchor.constraint(equalTo: pBarCont.bottomAnchor)
        ])
        let pStack = NSStackView(views: [pBarCont, pressureStatusRow])
        pStack.orientation = .vertical
        pStack.spacing = 6
        pressureCard.addContentSubview(pStack)
        container.addArrangedSubview(pressureCard)
        
        // 3. RAM Card
        ramBar.heightAnchor.constraint(equalToConstant: 10).isActive = true
        let ramBarContainer = NSView()
        ramBarContainer.translatesAutoresizingMaskIntoConstraints = false
        ramBarContainer.addSubview(ramBar)
        ramBar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            ramBar.leadingAnchor.constraint(equalTo: ramBarContainer.leadingAnchor),
            ramBar.trailingAnchor.constraint(equalTo: ramBarContainer.trailingAnchor),
            ramBar.topAnchor.constraint(equalTo: ramBarContainer.topAnchor),
            ramBar.bottomAnchor.constraint(equalTo: ramBarContainer.bottomAnchor)
        ])
        let ramRows = NSStackView(views: [appRow, wiredRow, compressedRow, freeRow])
        ramRows.orientation = .vertical
        ramRows.spacing = 4
        let ramStack = NSStackView(views: [ramBarContainer, ramRows])
        ramStack.orientation = .vertical
        ramStack.spacing = 8
        ramCard.addContentSubview(ramStack)
        container.addArrangedSubview(ramCard)
        
        // 4. Swap Card
        swapBar.heightAnchor.constraint(equalToConstant: 8).isActive = true
        let swapBarContainer = NSView()
        swapBarContainer.translatesAutoresizingMaskIntoConstraints = false
        swapBarContainer.addSubview(swapBar)
        swapBar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            swapBar.leadingAnchor.constraint(equalTo: swapBarContainer.leadingAnchor),
            swapBar.trailingAnchor.constraint(equalTo: swapBarContainer.trailingAnchor),
            swapBar.topAnchor.constraint(equalTo: swapBarContainer.topAnchor),
            swapBar.bottomAnchor.constraint(equalTo: swapBarContainer.bottomAnchor)
        ])
        let swapRows = NSStackView(views: [swapUsedRow, swapFreeRow])
        swapRows.orientation = .vertical
        swapRows.spacing = 4
        let swapStack = NSStackView(views: [swapBarContainer, swapRows])
        swapStack.orientation = .vertical
        swapStack.spacing = 8
        swapCard.addContentSubview(swapStack)
        container.addArrangedSubview(swapCard)
        
        // 5. Top Processes with App Icons
        topProcCard.addContentSubview(procTableView)
        container.addArrangedSubview(topProcCard)
        
        // 6. Action Footer
        let activityMonitorBtn = NSButton(title: "Open Activity Monitor (Memory)", target: self, action: #selector(openActivityMonitor))
        activityMonitorBtn.bezelStyle = .rounded
        activityMonitorBtn.controlSize = .small
        container.addArrangedSubview(activityMonitorBtn)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            container.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])
    }
    
    @objc private func openActivityMonitor() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
    }
    
    public func update(stats: MemoryStats) {
        let theme = AppPreferences.shared.colorTheme
        graphView.series1Color = theme.secondaryColor
        graphView.push(val1: stats.usedPercentage)
        
        pressureCard.setBadge(stats.pressureState.rawValue)
        pressureStatusRow.setValue(stats.pressureState.rawValue)
        let pressureColor: NSColor
        switch stats.pressureState {
        case .normal:   pressureColor = .systemGreen
        case .warning:  pressureColor = .systemYellow
        case .critical: pressureColor = .systemRed
        }
        pressureBar.setSegments([
            BarSegment(ratio: stats.pressurePercentage / 100.0, color: pressureColor)
        ])
        
        let gb = 1024.0 * 1024.0 * 1024.0
        let totalGB = Double(stats.totalBytes) / gb
        let usedGB = Double(stats.usedBytes) / gb
        ramCard.setBadge(String(format: "%.1f GB of %.0f GB (%.0f%%)", usedGB, totalGB, stats.usedPercentage))
        
        let appGB = Double(stats.appBytes) / gb
        let wiredGB = Double(stats.wiredBytes) / gb
        let compGB = Double(stats.compressedBytes) / gb
        let freeGB = Double(stats.freeBytes) / gb
        
        appRow.setValue(String(format: "%.2f GB", appGB))
        wiredRow.setValue(String(format: "%.2f GB", wiredGB))
        compressedRow.setValue(String(format: "%.2f GB", compGB))
        freeRow.setValue(String(format: "%.2f GB", freeGB))
        
        if stats.totalBytes > 0 {
            let total = Double(stats.totalBytes)
            ramBar.setSegments([
                BarSegment(ratio: Double(stats.appBytes) / total, color: .systemBlue),
                BarSegment(ratio: Double(stats.wiredBytes) / total, color: .systemIndigo),
                BarSegment(ratio: Double(stats.compressedBytes) / total, color: .systemTeal),
                BarSegment(ratio: Double(stats.freeBytes) / total, color: .systemGreen)
            ])
        }
        
        let mb = 1024.0 * 1024.0
        let swapUsedMB = Double(stats.swap.usedBytes) / mb
        let swapTotalMB = Double(stats.swap.totalBytes) / mb
        let swapFreeMB = Double(stats.swap.freeBytes) / mb
        
        swapCard.setBadge(String(format: "%.0f MB / %.0f MB", swapUsedMB, swapTotalMB))
        swapUsedRow.setValue(String(format: "%.1f MB", swapUsedMB))
        swapFreeRow.setValue(String(format: "%.1f MB", swapFreeMB))
        
        if stats.swap.totalBytes > 0 {
            let swapRatio = Double(stats.swap.usedBytes) / Double(stats.swap.totalBytes)
            swapBar.setSegments([
                BarSegment(ratio: swapRatio, color: .systemOrange),
                BarSegment(ratio: 1.0 - swapRatio, color: NSColor.secondaryLabelColor.withAlphaComponent(0.3))
            ])
        } else {
            swapBar.setSegments([])
        }
        
        // Update top processes with icons
        procTableView.update(processes: stats.topProcesses)
    }
}
