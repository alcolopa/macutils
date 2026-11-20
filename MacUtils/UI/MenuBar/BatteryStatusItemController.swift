import AppKit

@MainActor
public final class BatteryStatusItemController: NSObject, NSPopoverDelegate, MetricStatusItemControlling {
    public weak var statusItem: NSStatusItem?
    public let metricType: MetricType = .battery
    private let barView = BatteryBarItemView(frame: NSRect(x: 0, y: 0, width: 56, height: 22))
    private let popover = NSPopover()
    private let popoverVC = BatteryPopoverViewController()
    
    public func closePopover() {
        if popover.isShown { popover.close() }
    }
    
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
    
    public func syncLength() {
        guard let statusItem = statusItem else { return }
        statusItem.length = ceil(barView.intrinsicContentSize.width + BarChrome.extraWidth(for: .battery))
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
        popover.contentSize = NSSize(width: 340, height: 490)
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
            togglePopover()
        }
    }
    
    public func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.close()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
    
    public func update(stats: BatteryStats) {
        barView.updateBattery(stats: stats)
        popoverVC.update(stats: stats)
        syncLength()
    }
    
    public func popoverWillShow(_ notification: Notification) {
        onPopoverStateChanged?(true)
    }
    
    public func popoverDidClose(_ notification: Notification) {
        onPopoverStateChanged?(false)
    }
}

final class BatteryBarItemView: MenuBarItemContentView {
    private var stats: BatteryStats?
    private var percentage: Double = 100.0
    private var displayText: String = "100%"
    
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
        case .circularGauge: return 20
        case .barOnly: return 22
        case .verticalBar: return 10
        case .textOnly: return 32
        default: return 20
        }
    }
    
    public override var intrinsicContentSize: NSSize {
        NSSize(width: BarChrome.elementsWidth(for: .battery, widthFor: width(for:)), height: 22)
    }
    
    public func updateBattery(stats: BatteryStats) {
        self.stats = stats
        self.percentage = stats.percentage
        self.displayText = "\(Int(round(stats.percentage)))%"
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        let theme = AppPreferences.shared.colorTheme
        let color: NSColor = percentage <= 20.0 ? .systemRed : ((stats?.isCharging == true) ? .systemGreen : theme.primaryColor)
        
        BarChrome.draw(metric: .battery, in: self, widthFor: width(for:)) { [weak self] style, rect in
            guard let self = self else { return }
            
            switch style {
            case .textOnly:
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold),
                    .foregroundColor: NSColor.labelColor
                ]
                let str = NSAttributedString(string: self.displayText, attributes: attrs)
                let s = str.size()
                str.draw(at: CGPoint(x: rect.origin.x + (rect.width - s.width) / 2.0, y: rect.origin.y + (rect.height - s.height) / 2.0))
            case .barOnly:
                let barRect = CGRect(x: rect.origin.x + (rect.width - 16.0) / 2.0, y: rect.origin.y + (rect.height - 7.0) / 2.0, width: 16.0, height: 7.0)
                StatusItemRenderer.drawHorizontalBar(in: context, rect: barRect, percentage: self.percentage, fillColor: color)
            case .verticalBar:
                let barRect = CGRect(x: rect.origin.x + (rect.width - 7.0) / 2.0, y: rect.origin.y + (rect.height - 16.0) / 2.0, width: 7.0, height: 16.0)
                StatusItemRenderer.drawVerticalBar(in: context, rect: barRect, percentage: self.percentage, fillColor: color)
            case .circularGauge:
                let gaugeSize: CGFloat = 15.0
                let gaugeRect = CGRect(x: rect.origin.x + (rect.width - gaugeSize) / 2.0, y: rect.origin.y + (rect.height - gaugeSize) / 2.0, width: gaugeSize, height: gaugeSize)
                StatusItemRenderer.drawCircularGauge(in: context, rect: gaugeRect, percentage: self.percentage, fillColor: color)
            case .standard:
                let textW: CGFloat = 28
                let textRect = CGRect(x: rect.origin.x, y: rect.origin.y, width: textW, height: rect.height)
                let barRect = CGRect(x: rect.origin.x + textW, y: rect.origin.y + (rect.height - 7.0) / 2.0, width: rect.width - textW - 2.0, height: 7.0)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
                    .foregroundColor: NSColor.labelColor
                ]
                let str = NSAttributedString(string: self.displayText, attributes: attrs)
                let s = str.size()
                str.draw(at: CGPoint(x: textRect.origin.x + (textRect.width - s.width) / 2.0, y: textRect.origin.y + (textRect.height - s.height) / 2.0))
                StatusItemRenderer.drawHorizontalBar(in: context, rect: barRect, percentage: self.percentage, fillColor: color)
            default:
                break
            }
        }
    }
}
