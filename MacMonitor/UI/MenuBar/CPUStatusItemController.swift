import AppKit

@MainActor
public final class CPUStatusItemController: NSObject, NSPopoverDelegate {
    public let statusItem: NSStatusItem
    private let barView = CPUBarItemView(frame: NSRect(x: 0, y: 0, width: 56, height: 22))
    private let popover = NSPopover()
    private let popoverVC = CPUPopoverViewController()

    public func closePopover() { if popover.isShown { popover.close() } }
    
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
        statusItem.length = ceil(barView.intrinsicContentSize.width + BarChrome.extraWidth(for: .cpu))
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
        popover.contentSize = NSSize(width: 330, height: 420)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = popoverVC
        popover.delegate = self
    }
    
    @objc public func handleButtonClick(_ sender: AnyObject?) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
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
    
    public func update(stats: CPUStats) {
        barView.updateCPU(stats.totalUsage)
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

final class CPUBarItemView: NSView {
    private var recentValues: [Double] = []
    private var currentUsage: Double = 0.0
    private var lastPercentage: Int = -1
    
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
        case .standard, .multicolorCircle: return 22
        case .barOnly: return 22
        case .verticalBar: return 10
        case .circularGauge: return 20
        case .textOnly: return 34
        default: return 20
        }
    }
    
    public override var intrinsicContentSize: NSSize {
        NSSize(width: BarChrome.elementsWidth(for: .cpu, widthFor: width(for:)), height: 22)
    }
    
    public func updateCPU(_ usage: Double) {
        self.currentUsage = usage
        let rounded = Int(round(usage))
        recentValues.append(usage)
        if recentValues.count > 5 {
            recentValues.removeFirst()
        }
        lastPercentage = rounded
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        BarChrome.draw(metric: .cpu, in: self, widthFor: width(for:)) { style, rect in
            drawElement(style, in: rect, context: context)
        }
    }
    
    private func drawElement(_ style: MetricDisplayStyle, in rect: CGRect, context: CGContext) {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let textColor = isDark ? NSColor.white : NSColor.black
        
        switch style {
        case .barOnly:
            // Requested feature: Show only bars for CPU
            let barArea = CGRect(
                x: (rect.width - 18.0) / 2.0,
                y: (rect.height - 12.0) / 2.0,
                width: 18.0,
                height: 12.0
            )
            // Outline shows the full (100%) extent so each bar reads against its maximum
            let outline = CGPath(roundedRect: barArea.insetBy(dx: -2, dy: -2), cornerWidth: 3, cornerHeight: 3, transform: nil)
            context.saveGState()
            context.setStrokeColor(textColor.withAlphaComponent(0.55).cgColor)
            context.setLineWidth(1.0)
            context.addPath(outline)
            context.strokePath()
            context.restoreGState()
            StatusItemRenderer.drawBarsOnly(
                in: context,
                rect: barArea,
                values: recentValues,
                barCount: 4,
                primaryColor: textColor
            )
            
        case .verticalBar:
            let barRect = CGRect(x: (rect.width - 7.0) / 2.0, y: (rect.height - 16.0) / 2.0, width: 7.0, height: 16.0)
            StatusItemRenderer.drawVerticalBar(in: context, rect: barRect, percentage: currentUsage, fillColor: textColor)
            
        case .circularGauge:
            let gaugeSize: CGFloat = 15.0
            let gaugeRect = CGRect(
                x: (rect.width - gaugeSize) / 2.0,
                y: (rect.height - gaugeSize) / 2.0,
                width: gaugeSize,
                height: gaugeSize
            )
            StatusItemRenderer.drawCircularGauge(
                in: context,
                rect: gaugeRect,
                percentage: currentUsage,
                fillColor: textColor
            )
            
        case .textOnly:
            let text = "\(max(lastPercentage, 0))%"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold),
                .foregroundColor: textColor
            ]
            let attrStr = NSAttributedString(string: text, attributes: attrs)
            let strSize = attrStr.size()
            let textX = (rect.width - strSize.width) / 2.0
            let textY = (rect.height - strSize.height) / 2.0
            attrStr.draw(at: CGPoint(x: textX, y: textY))
            
        case .standard, .multicolorCircle:
            // Sparkline graph only; the percentage is its own (Text) element
            let sparkWidth: CGFloat = 16.0
            let sparkHeight: CGFloat = 11.0
            let sparkRect = CGRect(
                x: (rect.width - sparkWidth) / 2.0,
                y: (rect.height - sparkHeight) / 2.0,
                width: sparkWidth,
                height: sparkHeight
            )
            SparklineRenderer.render(in: context, rect: sparkRect, values: recentValues)
        default: break
        }
    }
}
