import AppKit

@MainActor
public final class NetworkStatusItemController: NSObject, NSPopoverDelegate, MetricStatusItemControlling {
    public weak var statusItem: NSStatusItem?
    public let metricType: MetricType = .network
    private let barView = NetworkBarItemView(frame: NSRect(x: 0, y: 0, width: 62, height: 22))
    private let popover = NSPopover()
    private let popoverVC = NetworkPopoverViewController()

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
        statusItem.length = ceil(barView.intrinsicContentSize.width + BarChrome.extraWidth(for: .network))
        barView.needsDisplay = true
    }
    
    private func setupButton() {
        guard let button = statusItem?.button else { return }
        button.subviews.forEach { $0.removeFromSuperview() }
        button.frame = NSRect(x: 0, y: 0, width: 62, height: 22)
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
        popover.contentSize = NSSize(width: 330, height: 420)
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
    
    public func update(stats: NetworkStats) {
        barView.updateNetwork(stats: stats)
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

final class NetworkBarItemView: MenuBarItemContentView {
    private var inSpeedText: String = "↓0K"
    private var outSpeedText: String = "↑0K"
    private var inFraction: Double = 0
    private var outFraction: Double = 0
    private var compactSpeedText: String = "0K"
    
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
        case .standard, .textOnly:
            return 30.0
        case .verticalBar:
            return 14.0
        default:
            return 30.0
        }
    }
    
    public override var intrinsicContentSize: NSSize {
        NSSize(width: BarChrome.elementsWidth(for: .network, widthFor: width(for:)), height: 22)
    }
    
    public func updateNetwork(stats: NetworkStats) {
        let inSec = UInt64(max(stats.bytesInPerSec, 0.0))
        let outSec = UInt64(max(stats.bytesOutPerSec, 0.0))
        let total = inSec + outSec
        
        func compactFormat(bytes: UInt64, arrow: String) -> String {
            let kb = Double(bytes) / 1024.0
            let mb = kb / 1024.0
            
            if mb >= 10.0 {
                return String(format: "%@%.0fM", arrow, mb)
            } else if mb >= 1.0 {
                return String(format: "%@%.1fM", arrow, mb)
            } else if kb >= 100.0 {
                return "\(arrow)\(Int(round(kb)))K"
            } else if kb >= 1.0 {
                return String(format: "%@%.0fK", arrow, kb)
            } else {
                return "\(arrow)0K"
            }
        }
        
        inSpeedText = compactFormat(bytes: inSec, arrow: "↓")
        outSpeedText = compactFormat(bytes: outSec, arrow: "↑")
        
        let kbTotal = Double(total) / 1024.0
        let mbTotal = kbTotal / 1024.0
        if mbTotal >= 1.0 {
            compactSpeedText = String(format: "%.1fM/s", mbTotal)
        } else {
            compactSpeedText = String(format: "%.0fK/s", kbTotal)
        }
        
        // Scale bars logarithmically: 1 KB/s (empty) .. 100 MB/s (full)
        func fraction(_ bytes: UInt64) -> Double {
            guard bytes > 1024 else { return 0 }
            return min(max(log10(Double(bytes) / 1024.0) / 5.0, 0), 1) * 100.0
        }
        inFraction = fraction(inSec)
        outFraction = fraction(outSec)
        
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        BarChrome.draw(metric: .network, in: self, widthFor: width(for:)) { style, rect in
            drawElement(style, in: rect)
        }
    }
    
    private func drawElement(_ style: MetricDisplayStyle, in rect: CGRect) {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let textColor = isDark ? NSColor.white : NSColor.black
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail
        
        if style == .textOnly {
            // Upload/download arrows on one line, truncating with ellipsis if > 30 pt
            let font = NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .semibold)
            let str = NSMutableAttributedString(
                string: "\(outSpeedText) \(inSpeedText)",
                attributes: [
                    .font: font,
                    .foregroundColor: textColor,
                    .paragraphStyle: paragraphStyle
                ]
            )
            let textRect = CGRect(x: 0, y: (rect.height - 12.0) / 2.0, width: rect.width, height: 12.0)
            str.draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            return
        }
        
        if style == .verticalBar, let context = NSGraphicsContext.current?.cgContext {
            let barW: CGFloat = 5.0, barH: CGFloat = 16.0, gap: CGFloat = 2.0
            let x = (rect.width - barW * 2 - gap) / 2.0
            let y = (rect.height - barH) / 2.0
            StatusItemRenderer.drawVerticalBar(in: context, rect: CGRect(x: x, y: y, width: barW, height: barH), percentage: outFraction, fillColor: textColor)
            StatusItemRenderer.drawVerticalBar(in: context, rect: CGRect(x: x + barW + gap, y: y, width: barW, height: barH), percentage: inFraction, fillColor: textColor)
            return
        }
        
        let font = NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .medium)
        
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ]
        
        let upStr = NSAttributedString(string: outSpeedText, attributes: attrs)
        let downStr = NSAttributedString(string: inSpeedText, attributes: attrs)
        
        let lineH: CGFloat = 10.0
        let topY = rect.height / 2.0 + 0.5
        let bottomY = 1.0
        
        let upRect = CGRect(x: 0, y: topY, width: rect.width, height: lineH)
        let downRect = CGRect(x: 0, y: bottomY, width: rect.width, height: lineH)
        
        upStr.draw(with: upRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        downStr.draw(with: downRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}
