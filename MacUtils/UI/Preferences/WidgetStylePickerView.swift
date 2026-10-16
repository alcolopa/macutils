import AppKit

@MainActor
public protocol WidgetStylePickerViewDelegate: AnyObject {
    func widgetStylePickerView(_ picker: WidgetStylePickerView, didSelectStyle style: MetricDisplayStyle)
}

@MainActor
public final class WidgetStyleChipView: NSView, NSDraggingSource {
    public static let stylePasteboardType = NSPasteboard.PasteboardType("com.macutils.widgetstyle")
    
    public let style: MetricDisplayStyle
    public let isSelected: Bool
    public var onSelect: (() -> Void)?
    
    private var mouseDownLocation: NSPoint?
    
    public init(style: MetricDisplayStyle, isSelected: Bool, previewView: NSView) {
        self.style = style
        self.isSelected = isSelected
        super.init(frame: .zero)
        setup(previewView: previewView)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setup(previewView: NSView) {
        wantsLayer = true
        layer?.cornerRadius = 6
        translatesAutoresizingMaskIntoConstraints = false
        
        if isSelected {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            layer?.borderWidth = 1.5
        } else {
            layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.4).cgColor
            layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.25).cgColor
            layer?.borderWidth = 1.0
        }
        
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        
        // Preview previewView inside a miniature stage
        let stage = NSView()
        stage.wantsLayer = true
        stage.layer?.cornerRadius = 4
        stage.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.6).cgColor
        stage.translatesAutoresizingMaskIntoConstraints = false
        stage.heightAnchor.constraint(equalToConstant: 26).isActive = true
        
        previewView.translatesAutoresizingMaskIntoConstraints = false
        stage.addSubview(previewView)
        NSLayoutConstraint.activate([
            previewView.centerXAnchor.constraint(equalTo: stage.centerXAnchor),
            previewView.centerYAnchor.constraint(equalTo: stage.centerYAnchor),
            stage.widthAnchor.constraint(greaterThanOrEqualToConstant: 54)
        ])
        
        stack.addArrangedSubview(stage)
        
        let label = NSTextField(labelWithString: style.displayName)
        label.font = NSFont.systemFont(ofSize: 11, weight: isSelected ? .semibold : .regular)
        label.textColor = isSelected ? NSColor.labelColor : NSColor.secondaryLabelColor
        label.alignment = .center
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 2
        label.preferredMaxLayoutWidth = 100
        stack.addArrangedSubview(label)
        
        if isSelected {
            let badge = NSTextField(labelWithString: "ACTIVE")
            badge.font = NSFont.systemFont(ofSize: 8.5, weight: .bold)
            badge.textColor = .controlAccentColor
            stack.addArrangedSubview(badge)
        }
        
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 96)
        ])
        
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil))
    }
    
    public override func mouseEntered(with event: NSEvent) {
        if !isSelected {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
        }
    }
    
    public override func mouseExited(with event: NSEvent) {
        if !isSelected {
            layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.4).cgColor
        }
    }
    
    public override func mouseDown(with event: NSEvent) {
        mouseDownLocation = convert(event.locationInWindow, from: nil)
    }
    
    public override func mouseUp(with event: NSEvent) {
        if let start = mouseDownLocation {
            let current = convert(event.locationInWindow, from: nil)
            if hypot(current.x - start.x, current.y - start.y) < 4.0 {
                onSelect?()
            }
        }
        mouseDownLocation = nil
    }
    
    public override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownLocation else { return }
        let current = convert(event.locationInWindow, from: nil)
        if hypot(current.x - start.x, current.y - start.y) > 3.0 {
            startDragging(with: event)
            mouseDownLocation = nil
        }
    }
    
    private func startDragging(with event: NSEvent) {
        let pbItem = NSPasteboardItem()
        pbItem.setString(style.rawValue, forType: Self.stylePasteboardType)
        
        let dragItem = NSDraggingItem(pasteboardWriter: pbItem)
        
        let snapshot = NSImage(size: bounds.size)
        snapshot.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            layer?.render(in: ctx)
        }
        snapshot.unlockFocus()
        
        dragItem.setDraggingFrame(NSRect(origin: .zero, size: bounds.size), contents: snapshot)
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }
    
    public nonisolated func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .copy
    }
}

/// One fixed-height row in the style list. Selection only changes colours, never the row size.
@MainActor
private final class WidgetStyleRowView: NSView, NSDraggingSource {
    let style: MetricDisplayStyle
    var onSelect: (() -> Void)?
    private let isSelected: Bool
    private var mouseDownPoint: NSPoint?
    
    init(style: MetricDisplayStyle, isSelected: Bool) {
        self.style = style
        self.isSelected = isSelected
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = isSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor
            : NSColor.clear.cgColor
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 30).isActive = true
        
        let label = NSTextField(labelWithString: style.displayName)
        label.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        label.textColor = isSelected ? .labelColor : .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        
        let check = NSImageView(image: NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil) ?? NSImage())
        check.contentTintColor = .controlAccentColor
        check.isHidden = !isSelected
        check.translatesAutoresizingMaskIntoConstraints = false
        addSubview(check)
        
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(lessThanOrEqualTo: check.leadingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            check.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            check.centerYAnchor.constraint(equalTo: centerYAnchor),
            check.widthAnchor.constraint(equalToConstant: 12)
        ])
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil))
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    override func mouseEntered(with event: NSEvent) {
        if !isSelected { layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor }
    }
    
    override func mouseExited(with event: NSEvent) {
        if !isSelected { layer?.backgroundColor = NSColor.clear.cgColor }
    }
    
    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint else { return }
        let now = convert(event.locationInWindow, from: nil)
        guard hypot(now.x - start.x, now.y - start.y) > 4 else { return }
        mouseDownPoint = nil
        
        let item = NSPasteboardItem()
        item.setString(style.rawValue, forType: WidgetStyleChipView.stylePasteboardType)
        let dragItem = NSDraggingItem(pasteboardWriter: item)
        dragItem.setDraggingFrame(bounds, contents: snapshotImage(of: self))
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }
    
    override func mouseUp(with event: NSEvent) {
        // A click (no drag) also applies the style
        if mouseDownPoint != nil, bounds.contains(convert(event.locationInWindow, from: nil)) { onSelect?() }
        mouseDownPoint = nil
    }
    
    nonisolated func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}

/// Fixed-width vertical list of the display styles available for a metric.
@MainActor
public final class WidgetStylePickerView: NSView {
    public weak var delegate: WidgetStylePickerViewDelegate?
    public static let listWidth: CGFloat = 210
    
    private let metric: MetricType
    private let stack = NSStackView()
    
    public init(metric: MetricType) {
        self.metric = metric
        super.init(frame: .zero)
        setup()
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.listWidth),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        refreshStyles()
    }
    
    public func refreshStyles() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        let active = AppPreferences.shared.barOptions(for: metric).styles
        for style in AppPreferences.availableStyles(for: metric) {
            let row = WidgetStyleRowView(style: style, isSelected: active.contains(style))
            row.onSelect = { [weak self, weak row] in
                guard let self = self, let row = row else { return }
                self.delegate?.widgetStylePickerView(self, didSelectStyle: row.style)
            }
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }
}
