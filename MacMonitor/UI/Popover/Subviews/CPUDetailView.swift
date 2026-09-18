import AppKit

public final class CPUDetailView: NSView {
    private let titleLabel = NSTextField(labelWithString: "CPU UTILIZATION")
    private let totalUsageLabel = NSTextField(labelWithString: "0%")
    private let coresStackView = NSStackView()
    private var coreViews: [CoreBarView] = []
    
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
        
        coresStackView.orientation = .vertical
        coresStackView.spacing = 4
        coresStackView.distribution = .fillEqually
        coresStackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(coresStackView)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            
            totalUsageLabel.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            totalUsageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            
            coresStackView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            coresStackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            coresStackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            coresStackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }
    
    public func update(stats: CPUStats) {
        totalUsageLabel.stringValue = String(format: "%.1f%%", stats.totalUsage)
        
        let loads = stats.perCoreLoads
        // Rebuild core views if count changed (e.g. initial load)
        if coreViews.count != loads.count {
            coresStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
            coreViews.removeAll()
            
            for load in loads {
                let bar = CoreBarView(coreIndex: load.coreIndex)
                coreViews.append(bar)
                coresStackView.addArrangedSubview(bar)
            }
        }
        
        for (index, load) in loads.enumerated() {
            if index < coreViews.count {
                coreViews[index].update(load: load)
            }
        }
    }
}

private final class CoreBarView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private let progressTrack = NSView()
    private let userBar = NSView()
    private let sysBar = NSView()
    
    private var userWidthConstraint: NSLayoutConstraint?
    private var sysWidthConstraint: NSLayoutConstraint?
    
    init(coreIndex: Int) {
        super.init(frame: .zero)
        setupView(coreIndex: coreIndex)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView(coreIndex: Int) {
        label.stringValue = "C\(coreIndex + 1)"
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        label.textColor = NSColor.secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        
        valueLabel.stringValue = "0%"
        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        valueLabel.textColor = NSColor.labelColor
        valueLabel.alignment = .right
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(valueLabel)
        
        progressTrack.wantsLayer = true
        progressTrack.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
        progressTrack.layer?.cornerRadius = 2
        progressTrack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(progressTrack)
        
        userBar.wantsLayer = true
        userBar.layer?.backgroundColor = NSColor.systemBlue.cgColor
        userBar.layer?.cornerRadius = 2
        userBar.translatesAutoresizingMaskIntoConstraints = false
        progressTrack.addSubview(userBar)
        
        sysBar.wantsLayer = true
        sysBar.layer?.backgroundColor = NSColor.systemTeal.cgColor
        sysBar.layer?.cornerRadius = 2
        sysBar.translatesAutoresizingMaskIntoConstraints = false
        progressTrack.addSubview(sysBar)
        
        let uWidth = userBar.widthAnchor.constraint(equalToConstant: 0)
        let sWidth = sysBar.widthAnchor.constraint(equalToConstant: 0)
        userWidthConstraint = uWidth
        sysWidthConstraint = sWidth
        
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.widthAnchor.constraint(equalToConstant: 26),
            
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueLabel.widthAnchor.constraint(equalToConstant: 34),
            
            progressTrack.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 4),
            progressTrack.trailingAnchor.constraint(equalTo: valueLabel.leadingAnchor, constant: -4),
            progressTrack.centerYAnchor.constraint(equalTo: centerYAnchor),
            progressTrack.heightAnchor.constraint(equalToConstant: 6),
            
            userBar.leadingAnchor.constraint(equalTo: progressTrack.leadingAnchor),
            userBar.topAnchor.constraint(equalTo: progressTrack.topAnchor),
            userBar.bottomAnchor.constraint(equalTo: progressTrack.bottomAnchor),
            uWidth,
            
            sysBar.leadingAnchor.constraint(equalTo: userBar.trailingAnchor),
            sysBar.topAnchor.constraint(equalTo: progressTrack.topAnchor),
            sysBar.bottomAnchor.constraint(equalTo: progressTrack.bottomAnchor),
            sWidth
        ])
    }
    
    func update(load: CoreLoad) {
        valueLabel.stringValue = String(format: "%.0f%%", load.totalUsagePercentage)
        
        let trackWidth = progressTrack.bounds.width
        if trackWidth > 0 {
            let userFrac = CGFloat(load.userPercentage / 100.0)
            let sysFrac = CGFloat(load.systemPercentage / 100.0)
            userWidthConstraint?.constant = trackWidth * userFrac
            sysWidthConstraint?.constant = trackWidth * sysFrac
        }
    }
}
