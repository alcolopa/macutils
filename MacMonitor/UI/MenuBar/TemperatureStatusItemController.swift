import AppKit

@MainActor
public final class TemperatureStatusItemController: NSObject, NSPopoverDelegate {
    public let statusItem: NSStatusItem
    private let barView = TemperatureBarItemView(frame: NSRect(x: 0, y: 0, width: 56, height: 22))
    private let popover = NSPopover()
    private let popoverVC = TemperaturePopoverViewController()
    
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
        statusItem.length = ceil(barView.intrinsicContentSize.width + BarChrome.extraWidth(for: .temperatures))
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
        popover.contentSize = NSSize(width: 340, height: 460)
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
    
    public func update(stats: TemperatureStats) {
        barView.updateTemperature(stats.cpuTemperature)
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

final class TemperatureBarItemView: NSView {
    private var currentTemp: Double = 45.0
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }
    
    public override var intrinsicContentSize: NSSize {
        let style = AppPreferences.shared.displayStyle(for: .temperatures)
        switch style {
        case .circularGauge:
            return NSSize(width: 22, height: 22)
        case .textOnly:
            return NSSize(width: 34, height: 22)
        default:
            return NSSize(width: 34, height: 22)
        }
    }
    
    public func updateTemperature(_ tempCelsius: Double) {
        self.currentTemp = tempCelsius
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        let rect = BarChrome.begin(metric: .temperatures, in: self)
        let style = AppPreferences.shared.displayStyle(for: .temperatures)
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let textColor = isDark ? NSColor.white : NSColor.black
        
        let isFahrenheit = AppPreferences.shared.temperatureUnit == .fahrenheit
        let displayVal = isFahrenheit ? (currentTemp * 9.0 / 5.0 + 32.0) : currentTemp
        let unitStr = isFahrenheit ? "°F" : "°C"
        let text = "\(Int(round(displayVal)))\(unitStr)"
        
        let tempColor: NSColor
        if currentTemp > 85.0 {
            tempColor = .systemRed
        } else if currentTemp > 70.0 {
            tempColor = .systemOrange
        } else {
            tempColor = textColor
        }
        
        switch style {
        case .circularGauge:
            let gaugeSize: CGFloat = 15.0
            let gaugeRect = CGRect(
                x: (rect.width - gaugeSize) / 2.0,
                y: (rect.height - gaugeSize) / 2.0,
                width: gaugeSize,
                height: gaugeSize
            )
            // Scale 30C - 100C as percentage 0..100
            let pct = min(max((currentTemp - 30.0) / 70.0 * 100.0, 0.0), 100.0)
            StatusItemRenderer.drawCircularGauge(
                in: context,
                rect: gaugeRect,
                percentage: pct,
                fillColor: tempColor
            )
            
        case .textOnly:
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold),
                .foregroundColor: tempColor
            ]
            let attrStr = NSAttributedString(string: text, attributes: attrs)
            let strSize = attrStr.size()
            let textX = (rect.width - strSize.width) / 2.0
            let textY = (rect.height - strSize.height) / 2.0
            attrStr.draw(at: CGPoint(x: textX, y: textY))
            
        default:
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold),
                .foregroundColor: tempColor
            ]
            let attrStr = NSAttributedString(string: text, attributes: attrs)
            let strSize = attrStr.size()
            attrStr.draw(at: CGPoint(x: (rect.width - strSize.width) / 2.0, y: (rect.height - strSize.height) / 2.0))
        }
    }
}
