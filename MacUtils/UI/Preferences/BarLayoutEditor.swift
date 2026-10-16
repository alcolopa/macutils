import AppKit

/// Renders a view into an image, used as the drag preview.
@MainActor
func snapshotImage(of view: NSView) -> NSImage {
    let size = view.bounds.size
    let image = NSImage(size: size)
    if size.width > 0, size.height > 0, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
        view.cacheDisplay(in: view.bounds, to: rep)
        image.addRepresentation(rep)
    }
    return image
}

/// A draggable Icon / Label / Value block shown in the preview bar or the hidden-parts tray.
@MainActor
final class BarPartChipView: NSView, NSDraggingSource {
    static let pasteboardType = NSPasteboard.PasteboardType("com.macutils.barpart")
    
    let part: BarPart
    private var mouseDownPoint: NSPoint?
    
    init(part: BarPart, content: NSView, dimmed: Bool) {
        self.part = part
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(dimmed ? 0.4 : 0.6).cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(dimmed ? 0.2 : 0.6).cgColor
        alphaValue = dimmed ? 0.6 : 1
        translatesAutoresizingMaskIntoConstraints = false
        
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            content.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 26)
        ])
        toolTip = "Drag to rearrange"
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint else { return }
        let now = convert(event.locationInWindow, from: nil)
        guard hypot(now.x - start.x, now.y - start.y) > 3 else { return }
        mouseDownPoint = nil
        
        let item = NSPasteboardItem()
        item.setString(part.token, forType: Self.pasteboardType)
        let dragItem = NSDraggingItem(pasteboardWriter: item)
        dragItem.setDraggingFrame(bounds, contents: snapshotImage(of: self))
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }
    
    nonisolated func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .move
    }
}

/// Drop target for `BarPartChipView`s; reports the part and the drop x position.
@MainActor
final class BarPartDropZone: NSView {
    var onDrop: ((BarPart, CGFloat) -> Void)?
    
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        translatesAutoresizingMaskIntoConstraints = false
        registerForDraggedTypes([BarPartChipView.pasteboardType, WidgetStyleChipView.stylePasteboardType])
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    /// Accepts both bar parts (icon/label/element chips) and styles dragged from the style list.
    private func part(from info: NSDraggingInfo) -> BarPart? {
        let pb = info.draggingPasteboard
        if let token = pb.string(forType: BarPartChipView.pasteboardType) { return BarPart(token: token) }
        if let raw = pb.string(forType: WidgetStyleChipView.stylePasteboardType),
           let style = MetricDisplayStyle(rawValue: raw) { return .element(style) }
        return nil
    }
    
    private func setHighlighted(_ on: Bool) {
        layer?.backgroundColor = on ? NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor : nil
    }
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard part(from: sender) != nil else { return [] }
        setHighlighted(true)
        return .move
    }
    
    override func draggingExited(_ sender: NSDraggingInfo?) { setHighlighted(false) }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        setHighlighted(false)
        guard let part = part(from: sender) else { return false }
        onDrop?(part, convert(sender.draggingLocation, from: nil).x)
        return true
    }
}

/// Lets the user build a widget by dragging its parts: add/reorder them in the bar, or drop them in the tray to hide.
@MainActor
final class BarLayoutEditor {
    let strip = BarPartDropZone()
    let tray = BarPartDropZone()
    var onChange: (() -> Void)?
    
    private let metric: MetricType
    private let prefs = AppPreferences.shared
    private let stripStack = NSStackView()
    private let trayStack = NSStackView()
    
    /// Every part this widget can show. Weather draws its own condition icon, so it has no separate icon part.
    private var available: [BarPart] {
        var parts: [BarPart] = (metric == .weather) ? [] : [.icon]
        parts.append(.label)
        parts += AppPreferences.availableStyles(for: metric).map { .element($0) }
        return parts
    }
    
    init(metric: MetricType) {
        self.metric = metric
        
        for (zone, stack) in [(strip, stripStack), (tray, trayStack)] {
            stack.orientation = .horizontal
            stack.alignment = .centerY
            stack.spacing = 8
            stack.translatesAutoresizingMaskIntoConstraints = false
            zone.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: zone.leadingAnchor, constant: 10),
                stack.centerYAnchor.constraint(equalTo: zone.centerYAnchor),
                stack.trailingAnchor.constraint(lessThanOrEqualTo: zone.trailingAnchor, constant: -10)
            ])
        }
        strip.heightAnchor.constraint(equalToConstant: 34).isActive = true
        tray.heightAnchor.constraint(greaterThanOrEqualToConstant: 34).isActive = true
        strip.onDrop = { [weak self] part, x in self?.dropOnStrip(part, x: x) }
        tray.onDrop = { [weak self] part, _ in self?.hide(part) }
        reload()
    }
    
    func reload() {
        let visible = prefs.barOptions(for: metric).order.filter { available.contains($0) }
        
        stripStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for part in visible { stripStack.addArrangedSubview(chip(for: part, dimmed: false)) }
        
        trayStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let hidden = available.filter { !visible.contains($0) }
        if hidden.isEmpty {
            let empty = NSTextField(labelWithString: "Everything is in the bar")
            empty.font = NSFont.systemFont(ofSize: 11)
            empty.textColor = .tertiaryLabelColor
            trayStack.addArrangedSubview(empty)
        }
        for part in hidden { trayStack.addArrangedSubview(chip(for: part, dimmed: true)) }
    }
    
    private func chip(for part: BarPart, dimmed: Bool) -> BarPartChipView {
        let content: NSView
        switch part {
        case .icon:
            let iv = NSImageView(image: NSImage(systemSymbolName: metric.iconSymbolName, accessibilityDescription: nil) ?? NSImage())
            iv.contentTintColor = .labelColor
            iv.widthAnchor.constraint(equalToConstant: 14).isActive = true
            iv.heightAnchor.constraint(equalToConstant: 14).isActive = true
            content = iv
        case .label:
            let l = NSTextField(labelWithString: BarChrome.shortLabel(for: metric))
            l.font = NSFont.systemFont(ofSize: 9, weight: .bold)
            l.textColor = .secondaryLabelColor
            content = l
        case .element(let style):
            content = SingleMetricWidgetPreviewView.makeSampleMiniView(metric: metric, style: style)
        }
        let chip = BarPartChipView(part: part, content: content, dimmed: dimmed)
        switch part {
        case .icon: chip.toolTip = "Icon"
        case .label: chip.toolTip = "Label"
        case .element(let style):
            switch style {
            case .textOnly:
                switch metric {
                case .weather: chip.toolTip = "Temperature"
                case .network: chip.toolTip = "Speeds (one line)"
                case .temperatures: chip.toolTip = "Temperature"
                default: chip.toolTip = "Percentage"
                }
            case .barOnly:
                switch metric {
                case .weather: chip.toolTip = "Condition icon"
                case .cpu: chip.toolTip = "Activity bars"
                default: chip.toolTip = "Horizontal bar"
                }
            case .verticalBar: chip.toolTip = "Vertical bar"
            case .circularGauge: chip.toolTip = "Circle"
            case .multicolorCircle: chip.toolTip = "Multicolour circle"
            case .humidity: chip.toolTip = "Humidity"
            case .wind: chip.toolTip = "Wind"
            case .feelsLike: chip.toolTip = "Feels like"
            case .highLow: chip.toolTip = "High / Low"
            case .rainChance: chip.toolTip = "Chance of rain"
            case .standard:
                switch metric {
                case .cpu: chip.toolTip = "Graph"
                case .network: chip.toolTip = "Speeds (stacked)"
                default: chip.toolTip = "Element"
                }
            }
        }
        return chip
    }
    
    private func dropOnStrip(_ part: BarPart, x: CGFloat) {
        guard available.contains(part) else { return }
        strip.layoutSubtreeIfNeeded()
        var order = prefs.barOptions(for: metric).order.filter { available.contains($0) }
        // Insertion index = number of other chips whose centre lies left of the drop point
        let index = stripStack.arrangedSubviews.compactMap { $0 as? BarPartChipView }
            .filter { $0.part != part && strip.convert(NSPoint(x: $0.bounds.midX, y: 0), from: $0).x < x }
            .count
        order.removeAll { $0 == part }
        order.insert(part, at: min(index, order.count))
        apply(order)
    }
    
    private func hide(_ part: BarPart) {
        var order = prefs.barOptions(for: metric).order
        order.removeAll { $0 == part }
        guard order.contains(where: { $0.style != nil }) else { return }   // keep at least one element
        apply(order)
    }
    
    private func apply(_ order: [BarPart]) {
        var o = prefs.barOptions(for: metric)
        o.order = order
        prefs.setBarOptions(o, for: metric)
        reload()
        onChange?()
    }
}
