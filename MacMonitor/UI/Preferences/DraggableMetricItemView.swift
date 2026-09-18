import AppKit

@MainActor
public protocol DraggableMetricItemViewDelegate: AnyObject {
    func draggableItemViewDidInitiateDrag(_ view: DraggableMetricItemView, metric: MetricType)
    func draggableItemView(_ view: DraggableMetricItemView, didDropMetric droppedMetric: MetricType, atTarget targetMetric: MetricType)
}

@MainActor
public final class DraggableMetricItemView: NSView, NSDraggingSource {
    public static let metricPasteboardType = NSPasteboard.PasteboardType("com.macmonitor.metrictype")
    
    public let metric: MetricType
    public weak var delegate: DraggableMetricItemViewDelegate?
    
    private var isHighlightedDropTarget: Bool = false
    private let contentStack = NSStackView()
    private var mouseDownLocation: NSPoint?
    
    public init(metric: MetricType, isFocusedMetric: Bool = false) {
        self.metric = metric
        super.init(frame: .zero)
        setup(isFocusedMetric: isFocusedMetric)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setup(isFocusedMetric: Bool) {
        wantsLayer = true
        layer?.cornerRadius = 4
        
        if isFocusedMetric {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.28).cgColor
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            layer?.borderWidth = 1.5
        } else {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.10).cgColor
            layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.2).cgColor
            layer?.borderWidth = 0.5
        }
        
        translatesAutoresizingMaskIntoConstraints = false
        
        contentStack.orientation = .horizontal
        contentStack.alignment = .centerY
        contentStack.spacing = 4
        contentStack.edgeInsets = NSEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)
        
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 24)
        ])
        
        registerForDraggedTypes([Self.metricPasteboardType])
    }
    
    public func setArrangedSubviews(_ views: [NSView]) {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        views.forEach { contentStack.addArrangedSubview($0) }
    }
    
    // MARK: - Dragging Source
    
    public override func mouseDown(with event: NSEvent) {
        mouseDownLocation = convert(event.locationInWindow, from: nil)
    }
    
    public override func mouseDragged(with event: NSEvent) {
        guard let startPoint = mouseDownLocation else { return }
        let currentPoint = convert(event.locationInWindow, from: nil)
        let distance = hypot(currentPoint.x - startPoint.x, currentPoint.y - startPoint.y)
        
        if distance > 3.0 {
            startDrag(with: event)
            mouseDownLocation = nil
        }
    }
    
    private func startDrag(with event: NSEvent) {
        delegate?.draggableItemViewDidInitiateDrag(self, metric: metric)
        
        let pbItem = NSPasteboardItem()
        pbItem.setString(metric.rawValue, forType: Self.metricPasteboardType)
        
        let dragItem = NSDraggingItem(pasteboardWriter: pbItem)
        
        let snapshot = imageSnapshot()
        let dragFrame = NSRect(origin: .zero, size: bounds.size)
        dragItem.setDraggingFrame(dragFrame, contents: snapshot)
        
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }
    
    public nonisolated func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .move
    }
    
    private func imageSnapshot() -> NSImage {
        let image = NSImage(size: bounds.size)
        image.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            layer?.render(in: ctx)
        }
        image.unlockFocus()
        return image
    }
    
    // MARK: - Dragging Destination
    
    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let sourceMetricRaw = sender.draggingPasteboard.string(forType: Self.metricPasteboardType),
              sourceMetricRaw != metric.rawValue else {
            return []
        }
        isHighlightedDropTarget = true
        layer?.borderColor = NSColor.systemBlue.cgColor
        layer?.borderWidth = 2.0
        layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.25).cgColor
        needsDisplay = true
        return .move
    }
    
    public override func draggingExited(_ sender: NSDraggingInfo?) {
        isHighlightedDropTarget = false
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.2).cgColor
        layer?.borderWidth = 0.5
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.10).cgColor
        needsDisplay = true
    }
    
    public override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return true
    }
    
    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isHighlightedDropTarget = false
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.2).cgColor
        layer?.borderWidth = 0.5
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.10).cgColor
        needsDisplay = true
        
        guard let sourceMetricRaw = sender.draggingPasteboard.string(forType: Self.metricPasteboardType),
              let sourceMetric = MetricType(rawValue: sourceMetricRaw) else {
            return false
        }
        
        delegate?.draggableItemView(self, didDropMetric: sourceMetric, atTarget: metric)
        return true
    }
}
