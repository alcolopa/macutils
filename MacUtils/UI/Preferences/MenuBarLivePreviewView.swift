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
        
        // Render visible items according to metricOrder wrapped in DraggableMetricItemView
        for metric in prefs.metricOrder {
            guard prefs.isMetricVisible(metric) else { continue }
            
            let isFocused = (focusedMetric == metric)
            let dragItem = DraggableMetricItemView(metric: metric, isFocusedMetric: isFocused)
            dragItem.delegate = self
            
            let style = prefs.displayStyle(for: metric)
            let miniView = SingleMetricWidgetPreviewView.makeSampleMiniView(metric: metric, style: style)
            dragItem.setArrangedSubviews([miniView])
            
            stack.addArrangedSubview(dragItem)
        }
        
        // Control Center / Date mockup on right
        let timeLabel = NSTextField(labelWithString: "Thu 11:30 AM")
        timeLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        timeLabel.textColor = NSColor.secondaryLabelColor
        stack.addArrangedSubview(timeLabel)
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
