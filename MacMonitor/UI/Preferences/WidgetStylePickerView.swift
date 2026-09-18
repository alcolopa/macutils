import AppKit

@MainActor
public protocol WidgetStylePickerViewDelegate: AnyObject {
    func widgetStylePickerView(_ picker: WidgetStylePickerView, didSelectStyle style: MetricDisplayStyle)
}

@MainActor
public final class WidgetStyleChipView: NSView, NSDraggingSource {
    public static let stylePasteboardType = NSPasteboard.PasteboardType("com.macmonitor.widgetstyle")
    
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

@MainActor
public final class WidgetStylePickerView: NSView {
    public weak var delegate: WidgetStylePickerViewDelegate?
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
        
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        refreshStyles()
    }
    
    public func refreshStyles() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        let styles = AppPreferences.availableStyles(for: metric)
        let currentStyle = AppPreferences.shared.displayStyle(for: metric)
        
        for style in styles {
            let sampleView = SingleMetricWidgetPreviewView.makeSampleMiniView(metric: metric, style: style)
            let chip = WidgetStyleChipView(style: style, isSelected: style == currentStyle, previewView: sampleView)
            chip.onSelect = { [weak self, weak chip] in
                guard let self = self, let chip = chip else { return }
                self.delegate?.widgetStylePickerView(self, didSelectStyle: chip.style)
            }
            stack.addArrangedSubview(chip)
        }
    }
}
