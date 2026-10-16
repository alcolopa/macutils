import AppKit

/// Floating, non-activating picker shown in the middle of the screen. It never takes focus, so the app
/// you are pasting into stays frontmost.
@MainActor
final class ClipboardPanel: NSPanel {
    private let listView = ClipboardListView()
    private var messageTimer: Timer?
    
    var onRowClicked: ((Int) -> Void)? {
        get { listView.onRowClicked }
        set { listView.onRowClicked = newValue }
    }
    
    init() {
        super.init(contentRect: NSRect(origin: .zero, size: ClipboardListView.panelSize),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        
        let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: ClipboardListView.panelSize))
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 18
        blur.layer?.masksToBounds = true
        blur.layer?.borderWidth = 1
        blur.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        listView.frame = blur.bounds
        listView.autoresizingMask = [.width, .height]
        blur.addSubview(listView)
        contentView = blur
    }
    
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    
    private func centerOnScreen(size: NSSize = ClipboardListView.panelSize) {
        setContentSize(size)
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2 + 40))
        }
    }
    
    func present(items: [ClipboardItem], selected: Int) {
        messageTimer?.invalidate()
        listView.message = nil
        listView.items = items
        listView.selected = selected
        centerOnScreen(size: ClipboardListView.size(forRows: items.count))
        orderFrontRegardless()
    }
    
    func update(selected: Int) { listView.selected = selected }
    
    /// Briefly shows a note instead of the list, then fades away.
    func showMessage(_ title: String, detail: String? = nil) {
        listView.message = (title, detail)
        centerOnScreen(size: NSSize(width: 460, height: 110))
        orderFrontRegardless()
        messageTimer?.invalidate()
        messageTimer = Timer.scheduledTimer(withTimeInterval: 2.4, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.orderOut(nil) }
        }
    }
}

@MainActor
final class ClipboardListView: NSView {
    static let visibleRows = 7
    static let rowHeight: CGFloat = 52
    static let headerHeight: CGFloat = 52
    static let footerHeight: CGFloat = 38
    static let panelSize = size(forRows: visibleRows)
    static func size(forRows rows: Int) -> NSSize {
        NSSize(width: 580, height: headerHeight + CGFloat(min(max(rows, 3), visibleRows)) * rowHeight + footerHeight)
    }
    
    private static var iconCache: [String: NSImage] = [:]
    
    var onRowClicked: ((Int) -> Void)?
    var message: (String, String?)? { didSet { needsDisplay = true } }
    var items: [ClipboardItem] = [] { didSet { needsDisplay = true } }
    var selected = 0 { didSet { needsDisplay = true } }
    
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    
    private var firstVisible: Int {
        let rows = Self.visibleRows
        guard items.count > rows else { return 0 }
        return min(max(selected - rows / 2, 0), items.count - rows)
    }
    
    private func rowRect(slot: Int) -> NSRect {
        NSRect(x: 10, y: Self.headerHeight + CGFloat(slot) * Self.rowHeight, width: bounds.width - 20, height: Self.rowHeight - 4)
    }
    
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        for slot in 0..<min(Self.visibleRows, items.count) where rowRect(slot: slot).contains(p) {
            onRowClicked?(firstVisible + slot)
            return
        }
    }
    
    private func sourceIcon(for item: ClipboardItem) -> NSImage? {
        guard let id = item.sourceBundleID else { return nil }
        if let cached = Self.iconCache[id] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        Self.iconCache[id] = icon
        return icon
    }
    
    private static func age(_ date: Date) -> String {
        let s = Int(-date.timeIntervalSinceNow)
        if s < 10 { return "now" }
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86400 { return "\(s / 3600)h" }
        return "\(s / 86400)d"
    }
    
    override func draw(_ dirtyRect: NSRect) {
        let titleAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: NSColor.labelColor]
        let hint: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11.5), .foregroundColor: NSColor.labelColor.withAlphaComponent(0.65)]
        
        if let (title, detail) = message {
            let t = NSAttributedString(string: title, attributes: titleAttrs)
            let centered = NSMutableParagraphStyle()
            centered.alignment = .center
            t.draw(at: NSPoint(x: (bounds.width - t.size().width) / 2, y: 24))
            if let detail {
                NSAttributedString(string: detail, attributes: hint.merging([.paragraphStyle: centered]) { $1 })
                    .draw(in: NSRect(x: 24, y: 54, width: bounds.width - 48, height: 40))
            }
            return
        }
        
        "Clipboard".draw(at: NSPoint(x: 22, y: 17), withAttributes: titleAttrs)
        let count = items.isEmpty ? "" : "\(selected + 1) of \(items.count)"
        let countSize = count.size(withAttributes: hint)
        count.draw(at: NSPoint(x: bounds.width - countSize.width - 22, y: 20), withAttributes: hint)
        
        NSColor.separatorColor.withAlphaComponent(0.5).setFill()
        NSRect(x: 0, y: Self.headerHeight - 1, width: bounds.width, height: 1).fill()
        NSRect(x: 0, y: bounds.height - Self.footerHeight, width: bounds.width, height: 1).fill()
        
        let footer = items.isEmpty
            ? "Copy something and it will show up here"
            : "Press V for next   ·   ↑ ↓ to move   ·   esc to cancel   ·   release ⌘⇧ to paste"
        let fSize = footer.size(withAttributes: hint)
        footer.draw(at: NSPoint(x: (bounds.width - fSize.width) / 2, y: bounds.height - Self.footerHeight + 12), withAttributes: hint)
        
        let start = firstVisible
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        for slot in 0..<min(Self.visibleRows, items.count) {
            let index = start + slot
            let item = items[index]
            let rect = rowRect(slot: slot)
            let isSelected = index == selected
            if isSelected {
                NSColor.controlAccentColor.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
            }
            let primary: NSColor = isSelected ? .white : .labelColor
            let secondary: NSColor = isSelected ? NSColor.white.withAlphaComponent(0.75) : .secondaryLabelColor
            
            // Leading visual: image thumbnail, or the app the item was copied from.
            let visual = NSRect(x: rect.minX + 12, y: rect.midY - 15, width: 30, height: 30)
            if let image = item.image {
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(roundedRect: visual, xRadius: 6, yRadius: 6).addClip()
                image.draw(in: visual, from: .zero, operation: .sourceOver, fraction: 1)
                NSGraphicsContext.restoreGraphicsState()
            } else if let icon = sourceIcon(for: item) {
                icon.draw(in: visual)
            } else if let symbol = NSImage(systemSymbolName: item.symbolName, accessibilityDescription: nil) {
                let tinted = symbol.withSymbolConfiguration(.init(pointSize: 18, weight: .regular))
                tinted?.isTemplate = true
                (isSelected ? NSColor.white : NSColor.secondaryLabelColor).set()
                tinted?.draw(in: visual.insetBy(dx: 4, dy: 4))
            }
            
            let ageText = Self.age(item.date)
            let ageAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: secondary]
            let ageSize = ageText.size(withAttributes: ageAttrs)
            ageText.draw(at: NSPoint(x: rect.maxX - ageSize.width - 14, y: rect.minY + 9), withAttributes: ageAttrs)
            
            let textX = rect.minX + 54
            let textWidth = rect.maxX - textX - ageSize.width - 28
            item.title.draw(with: NSRect(x: textX, y: rect.minY + 8, width: textWidth, height: 18),
                            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                            attributes: [.font: NSFont.systemFont(ofSize: 13.5, weight: .medium), .foregroundColor: primary, .paragraphStyle: para])
            item.subtitle.draw(with: NSRect(x: textX, y: rect.minY + 27, width: textWidth, height: 14),
                               options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                               attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: secondary, .paragraphStyle: para])
        }
    }
}
