import AppKit

@MainActor
public final class DiskStatusItemController: NSObject, NSPopoverDelegate, MetricStatusItemControlling {
    public weak var statusItem: NSStatusItem?
    public let metricType: MetricType = .disk
    private let barView = DiskBarItemView(frame: NSRect(x: 0, y: 0, width: 56, height: 22))
    private let popover = NSPopover()
    private let popoverVC = DiskPopoverViewController()

    public func closePopover() { if popover.isShown { popover.close() } }
    
    public var onPopoverStateChanged: (@Sendable (Bool) -> Void)?
    
    public override init() {
        super.init()
        setupPopover()
    }
    
    public func attach(to item: NSStatusItem) {
        detach()
        self.statusItem = item
        setupButton()
        syncLength()
    }
    
    public func detach() {
        closePopover()
        barView.removeFromSuperview()
        if let button = statusItem?.button {
            if button.target === self {
                button.target = nil
                button.action = nil
            }
        }
        self.statusItem = nil
    }
    
    public func destroy() {
        detach()
    }
    
    /// Sizes the status item to its content so widgets aren't spaced out for nothing.
    public func syncLength() {
        guard let statusItem = statusItem else { return }
        statusItem.length = ceil(barView.intrinsicContentSize.width + BarChrome.extraWidth(for: .disk))
        barView.needsDisplay = true
    }
    
    private func setupButton() {
        guard let button = statusItem?.button else { return }
        button.subviews.forEach { $0.removeFromSuperview() }
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
    
    private func setupPopover() {
        popover.contentSize = NSSize(width: 330, height: 400)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = popoverVC
        popover.delegate = self
    }
    
    @objc public func handleButtonClick(_ sender: AnyObject?) {
        guard let event = NSApp.currentEvent, let statusItem = statusItem else { return }
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
    
    private var lastStats: DiskStats?
    
    public func update(stats: DiskStats) {
        lastStats = stats
        barView.updateDisk(stats: stats)
        syncLength()
        if popover.isShown {
            popoverVC.update(stats: stats)
        }
    }
    
    // MARK: - NSPopoverDelegate
    public func popoverWillShow(_ notification: Notification) {
        if let last = lastStats {
            popoverVC.update(stats: last)
        }
        onPopoverStateChanged?(true)
    }
    
    public func popoverDidClose(_ notification: Notification) {
        onPopoverStateChanged?(false)
    }
}

final class DiskBarItemView: MenuBarItemContentView {
    private var usedPercentage: Double = 0.0
    private var freeGB: Double = 0.0
    
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
        case .standard, .multicolorCircle: return 48
        case .barOnly: return 22
        case .verticalBar: return 10
        case .circularGauge: return 20
        case .textOnly: return 34
        default: return 20
        }
    }
    
    public override var intrinsicContentSize: NSSize {
        NSSize(width: BarChrome.elementsWidth(for: .disk, widthFor: width(for:)), height: 22)
    }
    
    public func updateDisk(stats: DiskStats) {
        self.usedPercentage = stats.rootVolume.usedPercentage
        self.freeGB = Double(stats.rootVolume.freeBytes) / (1024.0 * 1024.0 * 1024.0)
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        BarChrome.draw(metric: .disk, in: self, widthFor: width(for:)) { style, rect in
            drawElement(style, in: rect, context: context)
        }
    }
    
    private func drawElement(_ style: MetricDisplayStyle, in rect: CGRect, context: CGContext) {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let textColor = isDark ? NSColor.white : NSColor.black
        
        switch style {
        case .barOnly:
            let barRect = CGRect(
                x: (rect.width - 16.0) / 2.0,
                y: (rect.height - 7.0) / 2.0,
                width: 16.0,
                height: 7.0
            )
            StatusItemRenderer.drawHorizontalBar(
                in: context,
                rect: barRect,
                percentage: usedPercentage,
                fillColor: textColor
            )
            
        case .verticalBar:
            let barRect = CGRect(x: (rect.width - 7.0) / 2.0, y: (rect.height - 16.0) / 2.0, width: 7.0, height: 16.0)
            StatusItemRenderer.drawVerticalBar(in: context, rect: barRect, percentage: usedPercentage, fillColor: textColor)
            
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
                percentage: usedPercentage,
                fillColor: textColor
            )
            
        case .textOnly:
            let text = "\(Int(round(usedPercentage)))%"
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
            let text = "\(Int(round(usedPercentage)))%"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold),
                .foregroundColor: textColor
            ]
            let attrStr = NSAttributedString(string: text, attributes: attrs)
            let strSize = attrStr.size()
            
            let textX: CGFloat = 2.0
            let textY = (rect.height - strSize.height) / 2.0
            attrStr.draw(at: CGPoint(x: textX, y: textY))
            
            // Disk capacity capsule bar
            let barWidth: CGFloat = 14.0
            let barHeight: CGFloat = 7.0
            let barRect = CGRect(
                x: rect.width - barWidth - 2.0,
                y: (rect.height - barHeight) / 2.0,
                width: barWidth,
                height: barHeight
            )
            
            let barColor: NSColor
            if usedPercentage > 90.0 {
                barColor = textColor
            } else if usedPercentage > 75.0 {
                barColor = textColor
            } else {
                barColor = textColor
            }
            
            StatusItemRenderer.drawHorizontalBar(
                in: context,
                rect: barRect,
                percentage: usedPercentage,
                fillColor: barColor
            )
        default: break
        }
    }
}
