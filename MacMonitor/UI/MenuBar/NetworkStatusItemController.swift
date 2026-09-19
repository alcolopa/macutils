import AppKit

@MainActor
public final class NetworkStatusItemController: NSObject, NSPopoverDelegate {
    public let statusItem: NSStatusItem
    private let barView = NetworkBarItemView(frame: NSRect(x: 0, y: 0, width: 62, height: 22))
    private let popover = NSPopover()
    private let popoverVC = NetworkPopoverViewController()

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
        statusItem.length = ceil(barView.intrinsicContentSize.width + BarChrome.extraWidth(for: .network))
        barView.needsDisplay = true
    }
    
    private func setupButton() {
        if let button = statusItem.button {
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

final class NetworkBarItemView: NSView {
    private var inSpeedText: String = "⇣0K"
    private var outSpeedText: String = "⇡0K"
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
        case .standard: return 52
        case .textOnly: return 70
        case .verticalBar: return 22
        default: return 52
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
        
        inSpeedText = compactFormat(bytes: inSec, arrow: "⇣")
        outSpeedText = compactFormat(bytes: outSec, arrow: "⇡")
        
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
        _ = textColor
        
        if style == .textOnly {
            // Upload/download arrows on one line, no icon
            let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
            let str = NSMutableAttributedString(
                string: outSpeedText,
                attributes: [.font: font, .foregroundColor: textColor])
            str.append(NSAttributedString(string: " ", attributes: [.font: font]))
            str.append(NSAttributedString(
                string: inSpeedText,
                attributes: [.font: font, .foregroundColor: textColor]))
            let size = str.size()
            str.draw(at: CGPoint(x: (rect.width - size.width) / 2.0, y: (rect.height - size.height) / 2.0))
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
        
        let upAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        let downAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        
        let upStr = NSAttributedString(string: outSpeedText, attributes: upAttrs)
        let downStr = NSAttributedString(string: inSpeedText, attributes: downAttrs)
        
        let topY = rect.height / 2.0 + 0.5
        let bottomY = 1.0
        
        upStr.draw(at: CGPoint(x: 2.0, y: topY))
        downStr.draw(at: CGPoint(x: 2.0, y: bottomY))
    }
}
