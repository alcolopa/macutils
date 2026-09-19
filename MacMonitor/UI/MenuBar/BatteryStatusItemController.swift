import AppKit

@MainActor
public final class BatteryStatusItemController: NSObject, NSPopoverDelegate {
    public let statusItem: NSStatusItem
    private let barView = BatteryBarItemView(frame: NSRect(x: 0, y: 0, width: 56, height: 22))
    private let popover = NSPopover()
    private let popoverVC = BatteryPopoverViewController()

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
        statusItem.length = ceil(barView.intrinsicContentSize.width + BarChrome.extraWidth(for: .battery))
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
    
    public func update(stats: BatteryStats) {
        barView.updateBattery(stats: stats)
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

final class BatteryBarItemView: NSView {
    private var capacity: Int = 100
    private var isCharging: Bool = false
    private var isPluggedIn: Bool = false
    
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
        case .standard: return 22
        case .textOnly: return 34
        case .barOnly: return 22
        case .verticalBar: return 10
        case .circularGauge, .multicolorCircle: return 20
        default: return 20
        }
    }
    
    public override var intrinsicContentSize: NSSize {
        NSSize(width: BarChrome.elementsWidth(for: .battery, widthFor: width(for:)), height: 22)
    }
    
    public func updateBattery(stats: BatteryStats) {
        self.capacity = stats.currentCapacity
        self.isCharging = stats.isCharging
        self.isPluggedIn = stats.isPluggedIn
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        BarChrome.draw(metric: .battery, in: self, widthFor: width(for:)) { style, rect in
            drawElement(style, in: rect, context: context)
        }
    }
    
    private func drawElement(_ style: MetricDisplayStyle, in rect: CGRect, context: CGContext) {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let textColor = isDark ? NSColor.white : NSColor.black
        let levelColor: NSColor = isCharging ? textColor : textColor
        
        switch style {
        case .verticalBar:
            let barRect = CGRect(x: (rect.width - 7.0) / 2.0, y: (rect.height - 16.0) / 2.0, width: 7.0, height: 16.0)
            StatusItemRenderer.drawVerticalBar(in: context, rect: barRect, percentage: Double(capacity), fillColor: levelColor)
            return
        case .barOnly:
            let barRect = CGRect(x: (rect.width - 18.0) / 2.0, y: (rect.height - 7.0) / 2.0, width: 18.0, height: 7.0)
            StatusItemRenderer.drawHorizontalBar(in: context, rect: barRect, percentage: Double(capacity), fillColor: levelColor)
            return
        case .circularGauge, .multicolorCircle:
            let size: CGFloat = 15.0
            let gaugeRect = CGRect(x: (rect.width - size) / 2.0, y: (rect.height - size) / 2.0, width: size, height: size)
            StatusItemRenderer.drawCircularGauge(in: context, rect: gaugeRect, percentage: Double(capacity), fillColor: levelColor)
            return
        case .textOnly:
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold),
                .foregroundColor: textColor
            ]
            let attrStr = NSAttributedString(string: "\(capacity)%", attributes: attrs)
            let strSize = attrStr.size()
            attrStr.draw(at: CGPoint(x: (rect.width - strSize.width) / 2.0, y: (rect.height - strSize.height) / 2.0))
            return
        case .standard:
            break
        default: break
        }
        
        // Draw Battery Icon
        let iconWidth: CGFloat = 17.0
        let iconHeight: CGFloat = 10.0
        let iconX: CGFloat = (rect.width - iconWidth) / 2.0
        let iconY = (rect.height - iconHeight) / 2.0
        
        // Outer body
        let bodyRect = CGRect(x: iconX, y: iconY, width: iconWidth - 2.0, height: iconHeight)
        let bodyPath = CGPath(roundedRect: bodyRect, cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)
        context.addPath(bodyPath)
        context.setStrokeColor(textColor.withAlphaComponent(0.85).cgColor)
        context.setLineWidth(1.0)
        context.strokePath()
        
        // Battery terminal cap
        let capRect = CGRect(x: bodyRect.maxX, y: iconY + 2.5, width: 1.5, height: iconHeight - 5.0)
        let capPath = CGPath(roundedRect: capRect, cornerWidth: 0.5, cornerHeight: 0.5, transform: nil)
        context.addPath(capPath)
        context.setFillColor(textColor.withAlphaComponent(0.85).cgColor)
        context.fillPath()
        
        // Fill level
        let fillFrac = CGFloat(min(max(Double(capacity) / 100.0, 0.0), 1.0))
        let maxFillW = bodyRect.width - 2.0
        let fillW = max(maxFillW * fillFrac, 1.0)
        let fillRect = CGRect(x: bodyRect.origin.x + 1.0, y: bodyRect.origin.y + 1.0, width: fillW, height: bodyRect.height - 2.0)
        
        let fillColor: CGColor
        if isCharging {
            fillColor = textColor.cgColor // Green
        } else if capacity <= 20 {
            fillColor = textColor.cgColor // Red
        } else {
            fillColor = textColor.cgColor
        }
        
        context.setFillColor(fillColor)
        let fillPath = CGPath(roundedRect: fillRect, cornerWidth: 0.8, cornerHeight: 0.8, transform: nil)
        context.addPath(fillPath)
        context.fillPath()
    }
}
