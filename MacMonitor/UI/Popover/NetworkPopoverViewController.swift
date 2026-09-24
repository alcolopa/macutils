import AppKit

public final class NetworkPopoverViewController: NSViewController {
    private let graphView = HistoryGraphView()
    private let speedCard = MetricCardView(title: "Bandwidth Speed")
    private let networkInfoCard = MetricCardView(title: "Interface & Connection")
    private let totalCard = MetricCardView(title: "Data Transferred")
    private let topProcCard = MetricCardView(title: "Apps Using Network", contentInsets: NSEdgeInsets(top: 8, left: 6, bottom: 8, right: 6))
    private let procTableView = ProcessTableView(mode: .network)
    
    private let downloadRow = MetricRowView(label: "Download (⇣):", color: .systemTeal)
    private let uploadRow = MetricRowView(label: "Upload (⇡):", color: .systemOrange)
    private let peakDownRow = MetricRowView(label: "Peak Download:", color: .systemTeal)
    private let peakUpRow = MetricRowView(label: "Peak Upload:", color: .systemOrange)
    
    private let ipRow = MetricRowView(label: "Local IPv4:", color: .systemGreen)
    private let interfaceRow = MetricRowView(label: "Primary Interface:", color: .systemBlue)
    
    private let totalInRow = MetricRowView(label: "Total Downloaded:", color: .systemTeal)
    private let totalOutRow = MetricRowView(label: "Total Uploaded:", color: .systemOrange)
    
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
    
    private var lastStats: NetworkStats?
    
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
        
        // 1. Graph Section
        let graphCard = MetricCardView(title: "Network Activity (60s)")
        graphView.heightAnchor.constraint(equalToConstant: 85).isActive = true
        graphView.maxDisplayValue = -1.0
        graphView.series1Color = AppPreferences.shared.colorTheme.primaryColor
        graphView.series2Color = AppPreferences.shared.colorTheme.contrastColor
        graphCard.addContentSubview(graphView)
        container.addArrangedSubview(graphCard)
        
        // 2. Current Speed Card
        let speedStack = NSStackView(views: [downloadRow, uploadRow, peakDownRow, peakUpRow])
        speedStack.orientation = .vertical
        speedStack.spacing = 4
        speedCard.addContentSubview(speedStack)
        container.addArrangedSubview(speedCard)
        
        // 3. Network Info Card
        let infoStack = NSStackView(views: [ipRow, interfaceRow])
        infoStack.orientation = .vertical
        infoStack.spacing = 4
        networkInfoCard.addContentSubview(infoStack)
        container.addArrangedSubview(networkInfoCard)
        
        // 4. Top Network Processes Card
        topProcCard.addContentSubview(procTableView)
        container.addArrangedSubview(topProcCard)
        
        // 5. Totals Card
        let totalStack = NSStackView(views: [totalInRow, totalOutRow])
        totalStack.orientation = .vertical
        totalStack.spacing = 4
        totalCard.addContentSubview(totalStack)
        container.addArrangedSubview(totalCard)
        
        // 6. Action Footer
        let activityMonitorBtn = NSButton(title: "Open Activity Monitor (Network)", target: self, action: #selector(openActivityMonitor))
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
    
    public func update(stats: NetworkStats) {
        lastStats = stats
        graphView.push(val1: stats.bytesInPerSec, val2: stats.bytesOutPerSec)
        
        guard isViewLoaded && view.window != nil else { return }
        updateVisibleDetails(stats: stats)
    }
    
    private func updateVisibleDetails(stats: NetworkStats) {
        let inSpeedStr = NetworkStats.formatSpeed(stats.bytesInPerSec)
        let outSpeedStr = NetworkStats.formatSpeed(stats.bytesOutPerSec)
        
        speedCard.setBadge("⇣ \(inSpeedStr)  ⇡ \(outSpeedStr)")
        downloadRow.setValue(inSpeedStr)
        uploadRow.setValue(outSpeedStr)
        
        peakDownRow.setValue(NetworkStats.formatSpeed(stats.peakBytesInPerSec))
        peakUpRow.setValue(NetworkStats.formatSpeed(stats.peakBytesOutPerSec))
        
        ipRow.setValue(stats.localIPAddress)
        interfaceRow.setValue(stats.primaryInterface)
        networkInfoCard.setBadge(stats.primaryInterface)
        
        // Update top processes using network
        procTableView.update(networkProcesses: stats.topProcesses)
        
        totalInRow.setValue(NetworkStats.formatTotalBytes(stats.totalBytesIn))
        totalOutRow.setValue(NetworkStats.formatTotalBytes(stats.totalBytesOut))
        totalCard.setBadge(NetworkStats.formatTotalBytes(stats.totalBytesIn + stats.totalBytesOut))
    }
}
