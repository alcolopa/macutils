import AppKit

@MainActor
public final class MenuBarLivePreviewView: NSView, DraggableMetricItemViewDelegate {
    private let stack = NSStackView()
    private let backgroundCard = NSBox()
    private let focusedMetric: MetricType?
    
    public init(focusedMetric: MetricType? = nil) {
        self.focusedMetric = focusedMetric
        super.init(frame: .zero)
        setup()
    }
    
    public override init(frame frameRect: NSRect) {
        self.focusedMetric = nil
        super.init(frame: frameRect)
        setup()
    }
    
    public required init?(coder: NSCoder) {
        self.focusedMetric = nil
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        
        backgroundCard.boxType = .custom
        backgroundCard.borderColor = NSColor.separatorColor.withAlphaComponent(0.3)
        backgroundCard.borderWidth = 1.0
        backgroundCard.cornerRadius = 8
        backgroundCard.fillColor = NSColor.windowBackgroundColor.withAlphaComponent(0.7)
        backgroundCard.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backgroundCard)
        
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 12, bottom: 4, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        backgroundCard.contentView = stack
        
        NSLayoutConstraint.activate([
            backgroundCard.topAnchor.constraint(equalTo: topAnchor),
            backgroundCard.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundCard.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundCard.bottomAnchor.constraint(equalTo: bottomAnchor),
            backgroundCard.heightAnchor.constraint(equalToConstant: 40)
        ])
        
        refreshPreview()
    }
    
    /// Natural width lets overview pages scroll without compressing the widgets.
    var contentWidth: CGFloat { stack.fittingSize.width + 24 }

    public func refreshPreview() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let prefs = AppPreferences.shared
        
        // macOS Apple Logo mockup on left
        let appleLabel = NSTextField(labelWithString: "")
        appleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        appleLabel.textColor = NSColor.secondaryLabelColor
        stack.addArrangedSubview(appleLabel)
        
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(spacer)
        
        for block in prefs.barBlockOrder {
            switch block {
            case .clipboard:
                if prefs.clipboardEnabled && prefs.showClipboardIcon {
                    addUtility(symbol: prefs.clipboardPaused ? "pause.circle" : prefs.clipboardIcon.symbolName, title: "Clipboard")
                }
            case .caffeinate:
                if prefs.showCaffeinate {
                    addUtility(symbol: CaffeinateManager.shared.isActive ? "cup.and.saucer.fill" : "cup.and.saucer", title: "Caffeinate")
                }
            case .monitors:
                for metric in prefs.metricOrder where prefs.isMetricVisible(metric) {
                    let dragItem = DraggableMetricItemView(metric: metric, isFocusedMetric: focusedMetric == metric)
                    dragItem.delegate = self
                    dragItem.toolTip = "\(metric.displayName) — drag to reorder monitors"
                    let options = prefs.barOptions(for: metric)
                    let parts: [NSView] = options.order.map { part in
                        switch part {
                        case .icon:
                            let icon = NSImageView(image: NSImage(systemSymbolName: metric.iconSymbolName, accessibilityDescription: metric.displayName) ?? NSImage())
                            icon.symbolConfiguration = .init(pointSize: options.iconSize.points, weight: .regular)
                            icon.contentTintColor = options.iconTint == .theme ? prefs.colorTheme.primaryColor : .labelColor
                            return icon
                        case .label:
                            let label = NSTextField(labelWithString: BarChrome.shortLabel(for: metric))
                            label.font = .systemFont(ofSize: 9, weight: .bold)
                            return label
                        case .element(let style):
                            return SingleMetricWidgetPreviewView.makeSampleMiniView(metric: metric, style: style)
                        }
                    }
                    dragItem.setArrangedSubviews(parts)
                    stack.addArrangedSubview(dragItem)
                }
            }
        }

        // Control Center / Date mockup on right
        let timeLabel = NSTextField(labelWithString: DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short))
        timeLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        timeLabel.textColor = NSColor.secondaryLabelColor
        stack.addArrangedSubview(timeLabel)
    }
    
    private func addUtility(symbol: String, title: String) {
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: title) ?? NSImage())
        icon.contentTintColor = .labelColor
        icon.toolTip = title
        stack.addArrangedSubview(icon)
    }

    // MARK: - DraggableMetricItemViewDelegate
    
    public func draggableItemViewDidInitiateDrag(_ view: DraggableMetricItemView, metric: MetricType) {
        // Drag in progress feedback
    }
    
    public func draggableItemView(_ view: DraggableMetricItemView, didDropMetric droppedMetric: MetricType, atTarget targetMetric: MetricType) {
        let prefs = AppPreferences.shared
        var order = prefs.metricOrder
        guard let sourceIndex = order.firstIndex(of: droppedMetric),
              let targetIndex = order.firstIndex(of: targetMetric),
              sourceIndex != targetIndex else { return }
        
        order.remove(at: sourceIndex)
        order.insert(droppedMetric, at: targetIndex)
        prefs.metricOrder = order
        refreshPreview()
    }
}
