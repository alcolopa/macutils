import AppKit

/// Floating, non-activating picker shown in the middle of the screen. It never takes focus, so the app
/// you are pasting into stays frontmost.
@MainActor
final class ClipboardPanel: NSPanel {
    private let listView = ClipboardListView()
    
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
        blur.layer?.cornerRadius = 16
        blur.layer?.masksToBounds = true
        listView.frame = blur.bounds
        listView.autoresizingMask = [.width, .height]
        blur.addSubview(listView)
        contentView = blur
    }
    
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    
    func present(items: [String], selected: Int) {
        listView.items = items
        listView.selected = selected
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            let size = ClipboardListView.panelSize
            setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2))
        }
        orderFrontRegardless()
    }
    
    func update(selected: Int) { listView.selected = selected }
}

@MainActor
final class ClipboardListView: NSView {
    static let panelSize = NSSize(width: 540, height: 44 + CGFloat(visibleRows) * rowHeight + 38)
    static let visibleRows = 8
    static let rowHeight: CGFloat = 36
    
    var onRowClicked: ((Int) -> Void)?
    var items: [String] = [] { didSet { needsDisplay = true } }
    var selected = 0 { didSet { needsDisplay = true } }
    
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    
    /// Index of the first row shown, keeping the selection in view.
    private var firstVisible: Int {
        let rows = Self.visibleRows
        guard items.count > rows else { return 0 }
        return min(max(selected - rows / 2, 0), items.count - rows)
    }
    
    private func rowRect(slot: Int) -> NSRect {
        NSRect(x: 10, y: 44 + CGFloat(slot) * Self.rowHeight, width: bounds.width - 20, height: Self.rowHeight - 2)
    }
    
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        for slot in 0..<min(Self.visibleRows, items.count) where rowRect(slot: slot).contains(p) {
            onRowClicked?(firstVisible + slot)
            return
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        let title: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.labelColor]
        let hint: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
        "Clipboard".draw(at: NSPoint(x: 20, y: 14), withAttributes: title)
        let hintText = "Hold ⌘⇧ and press V to cycle · release to paste · esc to cancel"
        let hintSize = hintText.size(withAttributes: hint)
        hintText.draw(at: NSPoint(x: bounds.width - hintSize.width - 20, y: bounds.height - hintSize.height - 12), withAttributes: hint)
        
        guard !items.isEmpty else {
            let empty = "Nothing copied yet. Copy some text and it will show up here."
            let size = empty.size(withAttributes: hint)
            empty.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: bounds.height / 2 - size.height / 2), withAttributes: hint)
            return
        }
        
        let start = firstVisible
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        for slot in 0..<min(Self.visibleRows, items.count) {
            let index = start + slot
            let rect = rowRect(slot: slot)
            let isSelected = index == selected
            if isSelected {
                NSColor.controlAccentColor.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
            }
            let textColor: NSColor = isSelected ? .white : .labelColor
            let numColor: NSColor = isSelected ? NSColor.white.withAlphaComponent(0.7) : .tertiaryLabelColor
            let num = "\(index + 1)"
            num.draw(at: NSPoint(x: rect.minX + 12, y: rect.midY - 7),
                     withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium), .foregroundColor: numColor])
            let preview = items[index]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ⏎ ")
                .replacingOccurrences(of: "\t", with: " ")
            let textRect = NSRect(x: rect.minX + 40, y: rect.midY - 8, width: rect.width - 54, height: 17)
            preview.draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                         attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: textColor, .paragraphStyle: para])
        }
    }
}
