import AppKit

@MainActor
public final class BatteryStatusItemController: NSObject, NSPopoverDelegate {
    public let statusItem: NSStatusItem
    private let barView = BatteryBarItemView(frame: NSRect(x: 0, y: 0, width: 56, height: 22))
    private let popover = NSPopover()
    private let popoverVC = BatteryPopoverViewController()
    
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
    
    public override var intrinsicContentSize: NSSize {
        let style = AppPreferences.shared.displayStyle(for: .battery)
        switch style {
        case .barOnly:
            return NSSize(width: 22, height: 22)
        case .textOnly:
            return NSSize(width: 34, height: 22)
        case .standard, .circularGauge, .multicolorCircle:
            return NSSize(width: 48, height: 22)
        }
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
        
        let rect = BarChrome.begin(metric: .battery, in: self)
        let style = AppPreferences.shared.displayStyle(for: .battery)
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let textColor = isDark ? NSColor.white : NSColor.black
        
        if style == .textOnly {
            let text = "\(capacity)%"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold),
                .foregroundColor: textColor
            ]
            let attrStr = NSAttributedString(string: text, attributes: attrs)
            let strSize = attrStr.size()
            let textX = (rect.width - strSize.width) / 2.0
            let textY = (rect.height - strSize.height) / 2.0
            attrStr.draw(at: CGPoint(x: textX, y: textY))
            return
        }
        
        // Draw Battery Icon
        let iconWidth: CGFloat = 17.0
        let iconHeight: CGFloat = 10.0
        let iconX: CGFloat = (style == .barOnly) ? (rect.width - iconWidth) / 2.0 : (rect.width - iconWidth - 2.0)
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
            fillColor = CGColor(red: 0.2, green: 0.8, blue: 0.2, alpha: 1.0) // Green
        } else if capacity <= 20 {
            fillColor = CGColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1.0) // Red
        } else {
            fillColor = textColor.cgColor
        }
        
        context.setFillColor(fillColor)
        let fillPath = CGPath(roundedRect: fillRect, cornerWidth: 0.8, cornerHeight: 0.8, transform: nil)
        context.addPath(fillPath)
        context.fillPath()
        
        // If standard, also draw percentage text on left
        if style == .standard || style == .circularGauge || style == .multicolorCircle {
            let text = "\(capacity)%"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold),
                .foregroundColor: textColor
            ]
            let attrStr = NSAttributedString(string: text, attributes: attrs)
            let strSize = attrStr.size()
            let textX: CGFloat = 2.0
            let textY = (rect.height - strSize.height) / 2.0
            attrStr.draw(at: CGPoint(x: textX, y: textY))
        }
    }
}
