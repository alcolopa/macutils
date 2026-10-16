import AppKit

public final class MemoryDetailView: NSView {
    private let titleLabel = NSTextField(labelWithString: "MEMORY UTILIZATION")
    private let totalUsageLabel = NSTextField(labelWithString: "0%")
    private let barContainer = NSView()
    
    // Segment bars
    private let appBar = NSView()
    private let wiredBar = NSView()
    private let compressedBar = NSView()
    
    private var appWidthConstraint: NSLayoutConstraint?
    private var wiredWidthConstraint: NSLayoutConstraint?
    private var compWidthConstraint: NSLayoutConstraint?
    
    // Metric labels
    private let usedLabel = NSTextField(labelWithString: "Used: 0 GB")
    private let wiredLabel = NSTextField(labelWithString: "Wired: 0 GB")
    private let compressedLabel = NSTextField(labelWithString: "Compressed: 0 GB")
    private let freeLabel = NSTextField(labelWithString: "Free: 0 GB")
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        wantsLayer = true
        
        titleLabel.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        titleLabel.textColor = NSColor.secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        
        totalUsageLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        totalUsageLabel.textColor = NSColor.labelColor
        totalUsageLabel.alignment = .right
        totalUsageLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(totalUsageLabel)
        
        // Progress bar container
        barContainer.wantsLayer = true
        barContainer.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
        barContainer.layer?.cornerRadius = 3
        barContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(barContainer)
        
        appBar.wantsLayer = true
        appBar.layer?.backgroundColor = NSColor.systemBlue.cgColor
        appBar.translatesAutoresizingMaskIntoConstraints = false
        barContainer.addSubview(appBar)
        
        wiredBar.wantsLayer = true
        wiredBar.layer?.backgroundColor = NSColor.systemIndigo.cgColor
        wiredBar.translatesAutoresizingMaskIntoConstraints = false
        barContainer.addSubview(wiredBar)
        
        compressedBar.wantsLayer = true
        compressedBar.layer?.backgroundColor = NSColor.systemTeal.cgColor
        compressedBar.translatesAutoresizingMaskIntoConstraints = false
        barContainer.addSubview(compressedBar)
        
        let appW = appBar.widthAnchor.constraint(equalToConstant: 0)
        let wiredW = wiredBar.widthAnchor.constraint(equalToConstant: 0)
        let compW = compressedBar.widthAnchor.constraint(equalToConstant: 0)
        appWidthConstraint = appW
        wiredWidthConstraint = wiredW
        compWidthConstraint = compW
        
        // Metrics 2x2 grid
        let leftStack = NSStackView(views: [usedLabel, compressedLabel])
        leftStack.orientation = .vertical
        leftStack.alignment = .leading
        leftStack.spacing = 3
        leftStack.translatesAutoresizingMaskIntoConstraints = false
        
        let rightStack = NSStackView(views: [wiredLabel, freeLabel])
        rightStack.orientation = .vertical
        rightStack.alignment = .leading
        rightStack.spacing = 3
        rightStack.translatesAutoresizingMaskIntoConstraints = false
        
        [usedLabel, wiredLabel, compressedLabel, freeLabel].forEach {
            $0.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
            $0.textColor = NSColor.secondaryLabelColor
        }
        
        let statsRow = NSStackView(views: [leftStack, rightStack])
        statsRow.orientation = .horizontal
        statsRow.distribution = .fillEqually
        statsRow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statsRow)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            
            totalUsageLabel.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            totalUsageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            
            barContainer.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            barContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            barContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            barContainer.heightAnchor.constraint(equalToConstant: 10),
            
            appBar.leadingAnchor.constraint(equalTo: barContainer.leadingAnchor),
            appBar.topAnchor.constraint(equalTo: barContainer.topAnchor),
            appBar.bottomAnchor.constraint(equalTo: barContainer.bottomAnchor),
            appW,
            
            wiredBar.leadingAnchor.constraint(equalTo: appBar.trailingAnchor),
            wiredBar.topAnchor.constraint(equalTo: barContainer.topAnchor),
            wiredBar.bottomAnchor.constraint(equalTo: barContainer.bottomAnchor),
            wiredW,
            
            compressedBar.leadingAnchor.constraint(equalTo: wiredBar.trailingAnchor),
            compressedBar.topAnchor.constraint(equalTo: barContainer.topAnchor),
            compressedBar.bottomAnchor.constraint(equalTo: barContainer.bottomAnchor),
            compW,
            
            statsRow.topAnchor.constraint(equalTo: barContainer.bottomAnchor, constant: 10),
            statsRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            statsRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            statsRow.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }
    
    public func update(stats: MemoryStats) {
        totalUsageLabel.stringValue = String(format: "%.1f%%", stats.usedPercentage)
        
        let gb: Double = 1024 * 1024 * 1024
        let appGB = Double(stats.activeBytes + stats.inactiveBytes) / gb
        let wiredGB = Double(stats.wiredBytes) / gb
        let compGB = Double(stats.compressedBytes) / gb
        let freeGB = Double(stats.freeBytes) / gb
        let totalGB = Double(stats.totalBytes) / gb
        
        usedLabel.stringValue = String(format: "App: %.2f GB", appGB)
        wiredLabel.stringValue = String(format: "Wired: %.2f GB", wiredGB)
        compressedLabel.stringValue = String(format: "Comp: %.2f GB", compGB)
        freeLabel.stringValue = String(format: "Free: %.2f GB (of %.0f)", freeGB, totalGB)
        
        let containerWidth = barContainer.bounds.width
        if containerWidth > 0 && stats.totalBytes > 0 {
            let total = Double(stats.totalBytes)
            let appRatio = Double(stats.activeBytes + stats.inactiveBytes) / total
            let wiredRatio = Double(stats.wiredBytes) / total
            let compRatio = Double(stats.compressedBytes) / total
            
            appWidthConstraint?.constant = containerWidth * CGFloat(appRatio)
            wiredWidthConstraint?.constant = containerWidth * CGFloat(wiredRatio)
            compWidthConstraint?.constant = containerWidth * CGFloat(compRatio)
        }
    }
}
