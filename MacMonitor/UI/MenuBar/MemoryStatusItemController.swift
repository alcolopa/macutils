import AppKit

@MainActor
public final class MemoryStatusItemController: NSObject, NSPopoverDelegate {
    public let statusItem: NSStatusItem
    private let barView = MemoryBarItemView(frame: NSRect(x: 0, y: 0, width: 56, height: 22))
    private let popover = NSPopover()
    private let popoverVC = MemoryPopoverViewController()
    
    public var onPopoverStateChanged: (@Sendable (Bool) -> Void)?
    
    public override init() {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        
        setupButton()
        setupPopover()
        syncLength()
    }
    
    /// Sizes the status item to its content so widgets aren't spaced out for nothing.
    public func syncLength() {
        statusItem.length = ceil(barView.intrinsicContentSize.width + BarChrome.extraWidth(for: .memory))
        barView.needsDisplay = true
    }
    
    private func setupButton() {
        if let button = statusItem.button {
            button.frame = NSRect(x: 0, y: 0, width: 56, height: 22)
            button.addSubview(barView)
            button.target = self
            button.action = #selector(handleButtonClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            
            barView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                barView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                barView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                barView.topAnchor.constraint(equalTo: button.topAnchor),
                barView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
            ])
        }
    }
    
    private func setupPopover() {
        popover.contentSize = NSSize(width: 340, height: 530)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = popoverVC
        popover.delegate = self
    }
    
    @objc public func handleButtonClick(_ sender: AnyObject?) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || (event.modifierFlags.contains(.control)) {
            let menu = PreferencesMenu.makeMenu()
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            if popover.isShown {
                popover.performClose(sender)
            } else if let button = statusItem.button {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }
    
    public func update(stats: MemoryStats) {
        barView.updateMemory(stats: stats)
        syncLength()
        _ = popoverVC.view // load eagerly so history accumulates while closed
        popoverVC.update(stats: stats)
    }
    
    // MARK: - NSPopoverDelegate
    public func popoverWillShow(_ notification: Notification) {
        onPopoverStateChanged?(true)
    }
    
    public func popoverDidClose(_ notification: Notification) {
        onPopoverStateChanged?(false)
    }
}

final class MemoryBarItemView: NSView {
    private var stats: MemoryStats?
    private var usedPercentage: Double = 0.0
    private var displayText: String = "0%"
    private var pressureColor: NSColor = .systemGreen
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }
    
    private func width(for style: MetricDisplayStyle) -> CGFloat {
        switch style {
        case .standard: return 48
        case .multicolorCircle, .circularGauge: return 20
        case .barOnly: return 22
        case .verticalBar: return 10
        case .textOnly: return 34
        default: return 20
        }
    }
    
    public override var intrinsicContentSize: NSSize {
        NSSize(width: BarChrome.elementsWidth(for: .memory, widthFor: width(for:)), height: 22)
    }
    
    public func updateMemory(stats: MemoryStats) {
        self.stats = stats
        self.usedPercentage = stats.usedPercentage
        
        switch stats.pressureState {
        case .normal:   self.pressureColor = .systemGreen
        case .warning:  self.pressureColor = .systemYellow
        case .critical: self.pressureColor = .systemRed
        }
        
        let mode = AppPreferences.shared.memoryDisplayMode
        switch mode {
        case .usedAmount:
            let gb = Double(stats.usedBytes) / (1024.0 * 1024.0 * 1024.0)
            if gb >= 10.0 {
                self.displayText = String(format: "%.0fG", gb)
            } else {
                self.displayText = String(format: "%.1fG", gb)
            }
        case .pressure:
            self.displayText = stats.pressureState == .normal ? "NORM" : (stats.pressureState == .warning ? "WARN" : "CRIT")
        case .percentage:
            self.displayText = "\(Int(round(stats.usedPercentage)))%"
        }
        
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        BarChrome.draw(metric: .memory, in: self, widthFor: width(for:)) { style, rect in
            drawElement(style, in: rect, context: context)
        }
    }
    
    private func drawElement(_ style: MetricDisplayStyle, in rect: CGRect, context: CGContext) {
        let theme = AppPreferences.shared.colorTheme
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let textColor = isDark ? NSColor.white : NSColor.black
        
        switch style {
        case .multicolorCircle:
            // Requested feature: Multicoloured circle for memory
            let circleSize: CGFloat = 16.0
            let circleRect = CGRect(
                x: (rect.width - circleSize) / 2.0,
                y: (rect.height - circleSize) / 2.0,
                width: circleSize,
                height: circleSize
            )
            
            if let stats = self.stats, stats.totalBytes > 0 {
                let total = Double(stats.totalBytes)
                let appFrac = Double(stats.appBytes) / total
                let wiredFrac = Double(stats.wiredBytes) / total
                let compFrac = Double(stats.compressedBytes) / total
                
                let segments: [(fraction: Double, color: NSColor)] = [
                    (appFrac, .systemBlue),
                    (wiredFrac, .systemIndigo),
                    (compFrac, .systemTeal)
                ]
                StatusItemRenderer.drawMulticolorCircle(
                    in: context,
                    rect: circleRect,
                    segments: segments,
                    lineWidth: 2.6
                )
            } else {
                let segments: [(fraction: Double, color: NSColor)] = [
                    (0.35, .systemBlue),
                    (0.15, .systemIndigo),
                    (0.10, .systemTeal)
                ]
                StatusItemRenderer.drawMulticolorCircle(
                    in: context,
                    rect: circleRect,
                    segments: segments,
                    lineWidth: 2.6
                )
            }
            
        case .circularGauge:
            let gaugeSize: CGFloat = 16.0
            let gaugeRect = CGRect(
                x: (rect.width - gaugeSize) / 2.0,
                y: (rect.height - gaugeSize) / 2.0,
                width: gaugeSize,
                height: gaugeSize
            )
            let color: NSColor = (AppPreferences.shared.memoryDisplayMode == .pressure) ? pressureColor : theme.secondaryColor
            StatusItemRenderer.drawCircularGauge(
                in: context,
                rect: gaugeRect,
                percentage: usedPercentage,
                fillColor: color
            )
            
        case .verticalBar:
            let barRect = CGRect(x: (rect.width - 7.0) / 2.0, y: (rect.height - 16.0) / 2.0, width: 7.0, height: 16.0)
            let color: NSColor = (AppPreferences.shared.memoryDisplayMode == .pressure) ? pressureColor : theme.secondaryColor
            StatusItemRenderer.drawVerticalBar(in: context, rect: barRect, percentage: usedPercentage, fillColor: color)
            
        case .barOnly:
            let barArea = CGRect(
                x: (rect.width - 18.0) / 2.0,
                y: (rect.height - 7.0) / 2.0,
                width: 18.0,
                height: 7.0
            )
            let color: NSColor = (AppPreferences.shared.memoryDisplayMode == .pressure) ? pressureColor : theme.secondaryColor
            StatusItemRenderer.drawHorizontalBar(
                in: context,
                rect: barArea,
                percentage: usedPercentage,
                fillColor: color
            )
            
        case .textOnly:
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold),
                .foregroundColor: textColor
            ]
            let attrStr = NSAttributedString(string: displayText, attributes: attrs)
            let strSize = attrStr.size()
            let textX = (rect.width - strSize.width) / 2.0
            let textY = (rect.height - strSize.height) / 2.0
            attrStr.draw(at: CGPoint(x: textX, y: textY))
            
        case .standard:
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold),
                .foregroundColor: textColor
            ]
            let attrStr = NSAttributedString(string: displayText, attributes: attrs)
            let strSize = attrStr.size()
            
            let textX: CGFloat = 2.0
            let textY = (rect.height - strSize.height) / 2.0
            attrStr.draw(at: CGPoint(x: textX, y: textY))
            
            // Miniature vertical memory meter
            let meterWidth: CGFloat = 7.0
            let meterHeight: CGFloat = 13.0
            let meterRect = CGRect(
                x: rect.width - meterWidth - 2.0,
                y: (rect.height - meterHeight) / 2.0,
                width: meterWidth,
                height: meterHeight
            )
            
            // Track
            context.setFillColor(NSColor.separatorColor.withAlphaComponent(0.3).cgColor)
            let trackPath = CGPath(roundedRect: meterRect, cornerWidth: 2.0, cornerHeight: 2.0, transform: nil)
            context.addPath(trackPath)
            context.fillPath()
            
            // Filled portion
            let fraction = CGFloat(min(max(usedPercentage / 100.0, 0.0), 1.0))
            let fillHeight = max(meterHeight * fraction, 1.0)
            let fillRect = CGRect(
                x: meterRect.origin.x,
                y: meterRect.origin.y,
                width: meterWidth,
                height: fillHeight
            )
            
            let fillColor: CGColor
            if AppPreferences.shared.memoryDisplayMode == .pressure {
                fillColor = pressureColor.cgColor
            } else if usedPercentage > 85.0 {
                fillColor = CGColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 0.9)
            } else if usedPercentage > 65.0 {
                fillColor = CGColor(red: 1.0, green: 0.58, blue: 0.0, alpha: 0.9)
            } else {
                fillColor = theme.secondaryColor.cgColor
            }
            
            context.setFillColor(fillColor)
            let fillPath = CGPath(roundedRect: fillRect, cornerWidth: 2.0, cornerHeight: 2.0, transform: nil)
            context.addPath(fillPath)
            context.fillPath()
        default: break
        }
    }
}
