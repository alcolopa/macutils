import AppKit

public final class DisplayPopoverViewController: NSViewController {
    private let overviewCard = MetricCardView(title: "Displays Connected", badge: "1 Active")
    private let arrangementCard = MetricCardView(title: "Screen Arrangement")
    private let arrangementView = DisplayArrangementThumbnailView()
    private let detailsCard = MetricCardView(title: "Display Details")
    private let detailsStack = NSStackView()
    
    private let scrollView = NSScrollView()
    private let container = FlippedStackView()
    
    public override func loadView() {
        let root = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 330, height: 440))
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
        
        // 1. Overview Card
        container.addArrangedSubview(overviewCard)
        
        // 2. Arrangement Visualizer
        arrangementView.heightAnchor.constraint(equalToConstant: 110).isActive = true
        arrangementCard.addContentSubview(arrangementView)
        container.addArrangedSubview(arrangementCard)
        
        // 3. Details Stack
        detailsStack.orientation = .vertical
        detailsStack.spacing = 8
        detailsCard.addContentSubview(detailsStack)
        container.addArrangedSubview(detailsCard)
        
        // 4. Open Displays Settings Button
        let openSettingsBtn = NSButton(title: "Displays Settings...", target: self, action: #selector(openDisplaySettings))
        openSettingsBtn.bezelStyle = .rounded
        openSettingsBtn.controlSize = .small
        container.addArrangedSubview(openSettingsBtn)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            container.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])
    }
    
    @objc private func openDisplaySettings() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/Displays.prefPane"))
    }
    
    public func update(stats: DisplayStats) {
        overviewCard.setBadge("\(stats.activeDisplayCount) connected")
        arrangementView.updateDisplays(stats.displays)
        
        detailsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        for (index, display) in stats.displays.enumerated() {
            let itemBox = NSBox()
            itemBox.boxType = .custom
                        itemBox.borderColor = NSColor.separatorColor.withAlphaComponent(0.2)
            itemBox.cornerRadius = 6
            itemBox.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.2)
            itemBox.translatesAutoresizingMaskIntoConstraints = false
            
            let itemStack = NSStackView()
            itemStack.orientation = .vertical
            itemStack.spacing = 3
            itemStack.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
            itemStack.translatesAutoresizingMaskIntoConstraints = false
            itemBox.contentView = itemStack
            
            let titleRow = MetricRowView(
                label: "\(display.isMain ? "★ " : "")\(display.name):",
                color: display.isMain ? .systemBlue : .systemTeal
            )
            titleRow.setValue(display.isBuiltIn ? "Built-In" : "External")
            itemStack.addArrangedSubview(titleRow)
            titleRow.widthAnchor.constraint(equalTo: itemStack.widthAnchor).isActive = true
            
            let resRow = MetricRowView(label: "Resolution:", color: .secondaryLabelColor)
            resRow.setValue("\(display.formattedResolution) (\(Int(display.backingScaleFactor))x Retina)")
            itemStack.addArrangedSubview(resRow)
            resRow.widthAnchor.constraint(equalTo: itemStack.widthAnchor).isActive = true
            
            let rateRow = MetricRowView(label: "Refresh Rate:", color: .systemOrange)
            rateRow.setValue(display.formattedRefreshRate)
            itemStack.addArrangedSubview(rateRow)
            rateRow.widthAnchor.constraint(equalTo: itemStack.widthAnchor).isActive = true
            
            let csRow = MetricRowView(label: "Color Profile:", color: .secondaryLabelColor)
            csRow.setValue(display.colorSpaceName)
            itemStack.addArrangedSubview(csRow)
            csRow.widthAnchor.constraint(equalTo: itemStack.widthAnchor).isActive = true
            
            detailsStack.addArrangedSubview(itemBox)
            itemBox.widthAnchor.constraint(equalTo: detailsStack.widthAnchor).isActive = true
        }
    }
}

public final class DisplayArrangementThumbnailView: NSView {
    private var displays: [DisplayInfo] = []
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 6
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }
    
    public func updateDisplays(_ displays: [DisplayInfo]) {
        self.displays = displays
        needsDisplay = true
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        let rect = bounds
        context.setFillColor(NSColor.windowBackgroundColor.withAlphaComponent(0.3).cgColor)
        context.fill(rect)
        
        guard !displays.isEmpty else { return }
        
        // Compute bounding box encompassing all screens
        var minX: CGFloat = .infinity
        var maxX: CGFloat = -.infinity
        var minY: CGFloat = .infinity
        var maxY: CGFloat = -.infinity
        
        for d in displays {
            minX = min(minX, d.bounds.minX)
            maxX = max(maxX, d.bounds.maxX)
            minY = min(minY, d.bounds.minY)
            maxY = max(maxY, d.bounds.maxY)
        }
        
        let totalW = max(maxX - minX, 1.0)
        let totalH = max(maxY - minY, 1.0)
        
        let padding: CGFloat = 12.0
        let availableW = rect.width - (padding * 2)
        let availableH = rect.height - (padding * 2)
        
        let scale = min(availableW / totalW, availableH / totalH)
        let offsetX = padding + (availableW - (totalW * scale)) / 2.0
        let offsetY = padding + (availableH - (totalH * scale)) / 2.0
        
        for d in displays {
            let screenX = offsetX + (d.bounds.minX - minX) * scale
            let screenY = offsetY + (d.bounds.minY - minY) * scale
            let screenW = d.bounds.width * scale
            let screenH = d.bounds.height * scale
            
            let screenRect = CGRect(x: screenX, y: screenY, width: screenW, height: screenH)
            
            // Monitor bezel
            context.setFillColor(NSColor.controlAccentColor.withAlphaComponent(d.isMain ? 0.35 : 0.2).cgColor)
            let path = CGPath(roundedRect: screenRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
            context.addPath(path)
            context.fillPath()
            
            context.setStrokeColor(d.isMain ? NSColor.systemBlue.cgColor : NSColor.separatorColor.cgColor)
            context.setLineWidth(1.5)
            context.addPath(path)
            context.strokePath()
            
            // Label inside monitor
            let label = d.isMain ? "Main" : "Display"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9, weight: .bold),
                .foregroundColor: NSColor.labelColor
            ]
            let str = NSAttributedString(string: label, attributes: attrs)
            let sSize = str.size()
            let lx = screenX + (screenW - sSize.width) / 2
            let ly = screenY + (screenH - sSize.height) / 2
            str.draw(at: CGPoint(x: lx, y: ly))
        }
    }
}
