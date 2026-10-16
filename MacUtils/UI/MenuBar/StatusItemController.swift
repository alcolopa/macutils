import AppKit

@MainActor
public final class StatusItemController: NSObject, NSPopoverDelegate {
    public let statusItem: NSStatusItem
    private let customView: StatusItemBarView
    private let popover: NSPopover
    private let popoverVC: PopoverViewController
    
    public var onPopoverStateChanged: (@Sendable (Bool) -> Void)?
    
    public override init() {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.customView = StatusItemBarView(frame: NSRect(x: 0, y: 0, width: 54, height: 22))
        self.popover = NSPopover()
        self.popoverVC = PopoverViewController()
        super.init()
        
        setupStatusItem()
        setupPopover()
    }
    
    private func setupStatusItem() {
        if let button = statusItem.button {
            button.frame = NSRect(x: 0, y: 0, width: 46, height: 22)
            button.addSubview(customView)
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            
            customView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                customView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                customView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                customView.topAnchor.constraint(equalTo: button.topAnchor),
                customView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
            ])
        }
    }
    
    private func setupPopover() {
        popover.contentSize = NSSize(width: 320, height: 380)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = popoverVC
        popover.delegate = self
    }
    
    @objc public func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            popover.performClose(sender)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
    
    public func updateMetrics(cpu: CPUStats, memory: MemoryStats) {
        customView.updateCPU(cpu.totalUsage)
        _ = popoverVC.view // load eagerly so history accumulates while closed
        popoverVC.updateMetrics(cpu: cpu, memory: memory)
    }
    
    // MARK: - NSPopoverDelegate
    public func popoverWillShow(_ notification: Notification) {
        onPopoverStateChanged?(true)
    }
    
    public func popoverDidClose(_ notification: Notification) {
        onPopoverStateChanged?(false)
    }
}

public final class StatusItemBarView: NSView {
    private var lastRoundedPercentage: Int = -1
    private var recentLoads: [Double] = []
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }
    
    public func updateCPU(_ totalUsage: Double) {
        let rounded = Int(round(totalUsage))
        
        recentLoads.append(totalUsage)
        if recentLoads.count > 5 {
            recentLoads.removeFirst()
        }
        
        // Redraw if rounded integer changes or sparkline updates
        lastRoundedPercentage = rounded
        needsDisplay = true
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        let bounds = self.bounds
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let textColor = isDark ? NSColor.white : NSColor.black
        
        // Text configuration: System Monospaced Digit, 9.5pt
        let percentageText = "\(max(lastRoundedPercentage, 0))%"
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .medium)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        
        let textString = NSAttributedString(string: percentageText, attributes: textAttributes)
        let textSize = textString.size()
        
        // Left side: Text representation
        let textRect = CGRect(
            x: 2.0,
            y: (bounds.height - textSize.height) / 2.0,
            width: textSize.width,
            height: textSize.height
        )
        textString.draw(in: textRect)
        
        // Right side: Miniature 5-bar sparkline
        let sparklineWidth: CGFloat = 16.0
        let sparklineHeight: CGFloat = 11.0
        let sparklineRect = CGRect(
            x: bounds.width - sparklineWidth - 2.0,
            y: (bounds.height - sparklineHeight) / 2.0,
            width: sparklineWidth,
            height: sparklineHeight
        )
        
        SparklineRenderer.render(in: context, rect: sparklineRect, values: recentLoads)
    }
}
