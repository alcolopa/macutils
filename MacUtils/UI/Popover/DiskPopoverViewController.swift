import AppKit

public final class DiskPopoverViewController: NSViewController {
    private let breakdownCard = MetricCardView(title: "Primary Volume", badge: "0 GB")
    private let storageBar = SegmentedProgressBar(frame: .zero)
    private let usedRow = MetricRowView(label: "Used Space:", color: .systemPurple)
    private let freeRow = MetricRowView(label: "Available Space:", color: .systemGreen)
    private let totalRow = MetricRowView(label: "Total Capacity:", color: .secondaryLabelColor)
    
    private let allVolumesCard = MetricCardView(title: "Mounted Disks")
    private let volumesStack = NSStackView()
    private var volumeViews: [VolumeItemView] = []
    
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
        
        // 1. Primary Volume Card
        storageBar.heightAnchor.constraint(equalToConstant: 10).isActive = true
        let barContainer = NSView()
        barContainer.translatesAutoresizingMaskIntoConstraints = false
        barContainer.addSubview(storageBar)
        storageBar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            storageBar.leadingAnchor.constraint(equalTo: barContainer.leadingAnchor),
            storageBar.trailingAnchor.constraint(equalTo: barContainer.trailingAnchor),
            storageBar.topAnchor.constraint(equalTo: barContainer.topAnchor),
            storageBar.bottomAnchor.constraint(equalTo: barContainer.bottomAnchor)
        ])
        
        let rows = NSStackView(views: [usedRow, freeRow, totalRow])
        rows.orientation = .vertical
        rows.spacing = 4
        
        let stack = NSStackView(views: [barContainer, rows])
        stack.orientation = .vertical
        stack.spacing = 8
        breakdownCard.addContentSubview(stack)
        container.addArrangedSubview(breakdownCard)
        
        // 2. All Volumes Card
        volumesStack.orientation = .vertical
        volumesStack.spacing = 6
        allVolumesCard.addContentSubview(volumesStack)
        container.addArrangedSubview(allVolumesCard)
        
        // 3. Activity Monitor Action
        let btn = NSButton(title: "Open Disk Utility", target: self, action: #selector(openDiskUtility))
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
    
    @objc private func openDiskUtility() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Disk Utility.app"))
    }
    
    public func update(stats: DiskStats) {
        let root = stats.rootVolume
        let usedFormatted = DiskStats.formatBytes(root.usedBytes)
        let totalFormatted = DiskStats.formatBytes(root.totalBytes)
        let freeFormatted = DiskStats.formatBytes(root.freeBytes)
        
        let sev = Severity.level(root.usedPercentage, warning: 75, danger: 90)
        breakdownCard.setBadge("\(usedFormatted) / \(totalFormatted) (\(Int(round(root.usedPercentage)))%)", tint: sev.textTint)
        usedRow.setValue(usedFormatted, tint: sev.textTint)
        freeRow.setValue(freeFormatted)
        totalRow.setValue(totalFormatted)
        
        if root.totalBytes > 0 {
            let usedRatio = Double(root.usedBytes) / Double(root.totalBytes)
            storageBar.setSegments([
                BarSegment(ratio: usedRatio, color: sev.color(normal: .systemPurple)),
                BarSegment(ratio: 1.0 - usedRatio, color: .systemGreen)
            ])
        }
        
        // Volume list
        let vols = stats.allVolumes
        if volumeViews.count != vols.count {
            volumesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
            volumeViews.removeAll()
            
            for vol in vols {
                let v = VolumeItemView(volume: vol)
                volumeViews.append(v)
                volumesStack.addArrangedSubview(v)
                v.widthAnchor.constraint(equalTo: volumesStack.widthAnchor).isActive = true
            }
        }
        
        for (i, vol) in vols.enumerated() {
            if i < volumeViews.count {
                volumeViews[i].update(volume: vol)
            }
        }
    }
}

final class VolumeItemView: NSView {
    private let nameLabel = NSTextField(labelWithString: "")
    private let bar = SegmentedProgressBar(frame: .zero)
    private let valueLabel = NSTextField(labelWithString: "")
    
    init(volume: VolumeInfo) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 16).isActive = true
        
        nameLabel.stringValue = volume.name
        nameLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        nameLabel.textColor = NSColor.secondaryLabelColor
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)
        
        bar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bar)
        
        valueLabel.stringValue = ""
        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        valueLabel.alignment = .right
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(valueLabel)
        
        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.widthAnchor.constraint(equalToConstant: 90),
            
            bar.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 4),
            bar.centerYAnchor.constraint(equalTo: centerYAnchor),
            bar.heightAnchor.constraint(equalToConstant: 6),
            bar.trailingAnchor.constraint(equalTo: valueLabel.leadingAnchor, constant: -6),
            
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueLabel.widthAnchor.constraint(equalToConstant: 65)
        ])
        
        update(volume: volume)
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }
    
    func update(volume: VolumeInfo) {
        let freeStr = DiskStats.formatBytes(volume.freeBytes)
        valueLabel.stringValue = "\(freeStr) free"
        if volume.totalBytes > 0 {
            let usedRatio = Double(volume.usedBytes) / Double(volume.totalBytes)
            let sev = Severity.level(usedRatio * 100, warning: 75, danger: 90)
            bar.setSegments([
                BarSegment(ratio: usedRatio, color: sev.color(normal: .systemPurple)),
                BarSegment(ratio: 1.0 - usedRatio, color: .systemGreen)
            ])
        }
    }
}
