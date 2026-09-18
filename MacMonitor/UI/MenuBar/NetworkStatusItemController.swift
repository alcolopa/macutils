import AppKit

@MainActor
public final class NetworkStatusItemController: NSObject, NSPopoverDelegate {
    public let statusItem: NSStatusItem
    private let barView = NetworkBarItemView(frame: NSRect(x: 0, y: 0, width: 62, height: 22))
    private let popover = NSPopover()
    private let popoverVC = NetworkPopoverViewController()
    
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
    private var compactSpeedText: String = "0K"
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }
    
    public override var intrinsicContentSize: NSSize {
        let style = AppPreferences.shared.displayStyle(for: .network)
        switch style {
        case .textOnly:
            return NSSize(width: 44, height: 22)
        default:
            return NSSize(width: 52, height: 22)
        }
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
        
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        let rect = BarChrome.begin(metric: .network, in: self)
        let style = AppPreferences.shared.displayStyle(for: .network)
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let textColor = isDark ? NSColor.white : NSColor.black
        
        if style == .textOnly {
            let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor
            ]
            let str = NSAttributedString(string: compactSpeedText, attributes: attrs)
            let size = str.size()
            let x = (rect.width - size.width) / 2.0
            let y = (rect.height - size.height) / 2.0
            str.draw(at: CGPoint(x: x, y: y))
            return
        }
        
        let font = NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .medium)
        
        let upAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.systemOrange
        ]
        let downAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.systemTeal
        ]
        
        let upStr = NSAttributedString(string: outSpeedText, attributes: upAttrs)
        let downStr = NSAttributedString(string: inSpeedText, attributes: downAttrs)
        
        let topY = rect.height / 2.0 + 0.5
        let bottomY = 1.0
        
        upStr.draw(at: CGPoint(x: 2.0, y: topY))
        downStr.draw(at: CGPoint(x: 2.0, y: bottomY))
    }
}
