import AppKit

@MainActor
public final class WeatherStatusItemController: NSObject, NSPopoverDelegate {
    public let statusItem: NSStatusItem
    private let barView = WeatherBarItemView(frame: NSRect(x: 0, y: 0, width: 64, height: 22))
    private let popover = NSPopover()
    private let popoverVC = WeatherPopoverViewController()

    public func closePopover() { if popover.isShown { popover.close() } }
    
    public var onPopoverStateChanged: (@Sendable (Bool) -> Void)?
    public var onRefreshRequested: (@Sendable () -> Void)?
    
    public override init() {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        
        setupButton()
        setupPopover()
        syncLength()
    }
    
    /// Sizes the status item to its content so widgets aren't spaced out for nothing.
    public func syncLength() {
        statusItem.length = ceil(barView.intrinsicContentSize.width + BarChrome.extraWidth(for: .weather))
        barView.needsDisplay = true
    }
    
    private func setupButton() {
        if let button = statusItem.button {
            button.frame = NSRect(x: 0, y: 0, width: 64, height: 22)
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
        popover.contentSize = NSSize(width: 360, height: 520)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = popoverVC
        popover.delegate = self
        
        popoverVC.onRefresh = { [weak self] in
            self?.onRefreshRequested?()
        }
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
    
    public func update(stats: WeatherStats) {
        barView.updateWeather(stats: stats)
        syncLength()
        _ = popoverVC.view // load eagerly so data is ready before first open
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

public final class WeatherBarItemView: NSView {
    private var stats: WeatherStats?
    
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
        case .textOnly: return 36
        case .barOnly: return 22
        case .humidity, .rainChance: return 40
        case .wind: return 48
        case .feelsLike: return 54
        case .highLow: return 32
        default: return 36
        }
    }
    
    public override var intrinsicContentSize: NSSize {
        NSSize(width: BarChrome.elementsWidth(for: .weather, widthFor: width(for:)), height: 22)
    }
    
    public func updateWeather(stats: WeatherStats) {
        self.stats = stats
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        BarChrome.draw(metric: .weather, in: self, widthFor: width(for:)) { style, rect in
            drawElement(style, in: rect, context: context)
        }
    }
    
    private func drawElement(_ style: MetricDisplayStyle, in rect: CGRect, context: CGContext) {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let textColor: NSColor = isDark ? .white : .black
        let multiConfig = NSImage.SymbolConfiguration.preferringMulticolor()
        let isFahrenheit = AppPreferences.shared.temperatureUnit == .fahrenheit
        
        guard let current = stats?.current else {
            // Unconfigured or loading placeholder
            let placeholder = "--°"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            let str = NSAttributedString(string: placeholder, attributes: attrs)
            let strSize = str.size()
            
            if style == .barOnly {
                if let baseImg = NSImage(systemSymbolName: "cloud.sun.fill", accessibilityDescription: nil),
                   let img = baseImg.withSymbolConfiguration(multiConfig) {
                    let iconRect = CGRect(x: (rect.width - 15) / 2.0, y: (rect.height - 15) / 2.0, width: 15, height: 15)
                    img.draw(in: iconRect)
                }
            } else {
                let x = (rect.width - strSize.width) / 2.0
                let y = (rect.height - strSize.height) / 2.0
                str.draw(at: CGPoint(x: x, y: y))
            }
            return
        }
        
        let tempVal = isFahrenheit ? (current.temperature * 9.0 / 5.0 + 32.0) : current.temperature
        let unitStr = isFahrenheit ? "°F" : "°C"
        let tempStr = "\(Int(round(tempVal)))\(unitStr)"
        let symbol = WeatherIconMapper.sfSymbol(for: current.condition.icon, conditionId: current.condition.id)
        let condColor = WeatherIconMapper.conditionColor(for: current.condition.id, isNight: current.condition.icon.hasSuffix("n"))
        
        switch style {
        case .barOnly:
            if let baseImg = NSImage(systemSymbolName: symbol, accessibilityDescription: current.condition.description) {
                let img = baseImg.withSymbolConfiguration(multiConfig) ?? baseImg
                let iconRect = CGRect(x: (rect.width - 16) / 2.0, y: (rect.height - 16) / 2.0, width: 16, height: 16)
                img.draw(in: iconRect)
            }
            
        case .textOnly:
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold),
                .foregroundColor: textColor
            ]
            let attrStr = NSAttributedString(string: tempStr, attributes: attrs)
            let strSize = attrStr.size()
            let x = (rect.width - strSize.width) / 2.0
            let y = (rect.height - strSize.height) / 2.0
            attrStr.draw(at: CGPoint(x: x, y: y))
            
        case .verticalBar:
            let pct = min(max((current.temperature + 10.0) / 50.0 * 100.0, 0.0), 100.0)
            let barRect = CGRect(x: (rect.width - 7.0) / 2.0, y: (rect.height - 16.0) / 2.0, width: 7.0, height: 16.0)
            StatusItemRenderer.drawVerticalBar(in: context, rect: barRect, percentage: pct, fillColor: condColor)
            
        case .humidity:
            drawReadout("\(current.humidity)%", symbol: "humidity", in: rect, color: textColor)
            
        case .rainChance:
            let chance = Int(round((stats?.forecast.first?.precipitationChance ?? 0) * 100))
            drawReadout("\(chance)%", symbol: "umbrella", in: rect, color: textColor)
            
        case .wind:
            let text = isFahrenheit
                ? "\(Int(round(current.windSpeed * 2.23694))) mph"
                : "\(Int(round(current.windSpeed * 3.6))) km/h"
            drawReadout(text, symbol: "wind", in: rect, color: textColor)
            
        case .feelsLike:
            let feels = isFahrenheit ? (current.feelsLike * 9.0 / 5.0 + 32.0) : current.feelsLike
            drawReadout("Feels \(Int(round(feels)))°", symbol: nil, in: rect, color: textColor)
            
        case .highLow:
            func t(_ c: Double) -> String { "\(Int(round(isFahrenheit ? c * 9.0 / 5.0 + 32.0 : c)))°" }
            let font = NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .semibold)
            let hi = NSAttributedString(string: "↑" + t(current.tempMax), attributes: [.font: font, .foregroundColor: textColor])
            let lo = NSAttributedString(string: "↓" + t(current.tempMin), attributes: [.font: font, .foregroundColor: textColor])
            hi.draw(at: CGPoint(x: (rect.width - hi.size().width) / 2.0, y: rect.height / 2.0 + 0.5))
            lo.draw(at: CGPoint(x: (rect.width - lo.size().width) / 2.0, y: 1.0))
            
        case .circularGauge:
            // Gauge scaled by temperature comfort (e.g. -10C to 40C)
            let pct = min(max((current.temperature + 10.0) / 50.0 * 100.0, 0.0), 100.0)
            let gaugeSize: CGFloat = 16.0
            let gaugeRect = CGRect(
                x: (rect.width - gaugeSize) / 2.0,
                y: (rect.height - gaugeSize) / 2.0,
                width: gaugeSize,
                height: gaugeSize
            )
            StatusItemRenderer.drawCircularGauge(in: context, rect: gaugeRect, percentage: pct, fillColor: condColor)
            
        default:
            // Standard: Symbol + Temp
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: textColor
            ]
            let attrStr = NSAttributedString(string: tempStr, attributes: attrs)
            let strSize = attrStr.size()
            
            let iconSize: CGFloat = 14.0
            let spacing: CGFloat = 3.0
            let totalWidth = iconSize + spacing + strSize.width
            let startX = max(1.0, (rect.width - totalWidth) / 2.0)
            
            if let baseImg = NSImage(systemSymbolName: symbol, accessibilityDescription: current.condition.description) {
                let img = baseImg.withSymbolConfiguration(multiConfig) ?? baseImg
                let iconRect = CGRect(x: startX, y: (rect.height - iconSize) / 2.0, width: iconSize, height: iconSize)
                img.draw(in: iconRect)
            }
            
            let textX = startX + iconSize + spacing
            let textY = (rect.height - strSize.height) / 2.0
            attrStr.draw(at: CGPoint(x: textX, y: textY))
        }
    }
    
    /// Text readout with an optional small leading SF Symbol, centred in `rect`.
    private func drawReadout(_ text: String, symbol: String?, in rect: CGRect, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: color
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        var iconW: CGFloat = 0
        var icon: NSImage?
        if let symbol,
           let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .medium)
                .applying(NSImage.SymbolConfiguration(paletteColors: [color.withAlphaComponent(0.8)]))) {
            icon = img
            iconW = 10 + 2
        }
        let startX = (rect.width - (iconW + size.width)) / 2.0
        icon?.draw(in: CGRect(x: startX, y: (rect.height - 10) / 2.0, width: 10, height: 10))
        str.draw(at: CGPoint(x: startX + iconW, y: (rect.height - size.height) / 2.0))
    }
}
