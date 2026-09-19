import AppKit

@MainActor
public final class DisplayStatusItemController: NSObject, NSPopoverDelegate {
    public let statusItem: NSStatusItem
    private let barView = DisplayBarItemView(frame: NSRect(x: 0, y: 0, width: 56, height: 22))
    private let popover = NSPopover()
    private let popoverVC = DisplayPopoverViewController()
    
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
        statusItem.length = ceil(barView.intrinsicContentSize.width + BarChrome.extraWidth(for: .displays))
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
        popover.contentSize = NSSize(width: 350, height: 460)
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
    
    public func update(stats: DisplayStats) {
        barView.updateDisplays(stats: stats)
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

final class DisplayBarItemView: NSView {
    private var displayCount: Int = 1
    
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
        case .verticalBar: return CGFloat(min(displayCount, 4)) * 7.0 + 3.0
        default: return 20
        }
    }
    
    public override var intrinsicContentSize: NSSize {
        NSSize(width: BarChrome.elementsWidth(for: .displays, widthFor: width(for:)), height: 22)
    }
    
    public func updateDisplays(stats: DisplayStats) {
        self.displayCount = max(stats.activeDisplayCount, 1)
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        BarChrome.draw(metric: .displays, in: self, widthFor: width(for:)) { style, rect in
            drawElement(style, in: rect)
        }
    }
    
    private func drawElement(_ style: MetricDisplayStyle, in rect: CGRect) {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let textColor = isDark ? NSColor.white : NSColor.black
        
        if style == .verticalBar, let context = NSGraphicsContext.current?.cgContext {
            // One full bar per active display
            let barW: CGFloat = 5.0, barH: CGFloat = 16.0, gap: CGFloat = 2.0
            let n = CGFloat(min(displayCount, 4))
            let totalW = n * barW + (n - 1) * gap
            for i in 0..<Int(n) {
                let r = CGRect(x: (rect.width - totalW) / 2.0 + CGFloat(i) * (barW + gap), y: (rect.height - barH) / 2.0, width: barW, height: barH)
                StatusItemRenderer.drawVerticalBar(in: context, rect: r, percentage: 100, fillColor: textColor)
            }
            return
        }
        
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold),
            .foregroundColor: textColor
        ]
        let attrStr = NSAttributedString(string: "\(displayCount)", attributes: attrs)
        let strSize = attrStr.size()
        attrStr.draw(at: CGPoint(x: (rect.width - strSize.width) / 2.0, y: (rect.height - strSize.height) / 2.0))
    }
}
