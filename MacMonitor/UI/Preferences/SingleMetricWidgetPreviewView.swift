import AppKit

@MainActor
public protocol SingleMetricWidgetPreviewDelegate: AnyObject {
    func singleMetricWidgetPreview(_ preview: SingleMetricWidgetPreviewView, didDropStyle style: MetricDisplayStyle)
    func singleMetricWidgetPreviewDidRequestMoveLeft(_ preview: SingleMetricWidgetPreviewView)
    func singleMetricWidgetPreviewDidRequestMoveRight(_ preview: SingleMetricWidgetPreviewView)
}

@MainActor
public final class SingleMetricWidgetPreviewView: NSView {
    public weak var delegate: SingleMetricWidgetPreviewDelegate?
    
    private let metric: MetricType
    private let liveContainer = NSView()
    private let dropTargetCard = NSBox()
    private let dropHintLabel = NSTextField(labelWithString: "Drop style here to apply")
    private let placementLabel = NSTextField(labelWithString: "")
    private let leftBtn = NSButton(title: "◀ Move Left", target: nil, action: nil)
    private let rightBtn = NSButton(title: "Move Right ▶", target: nil, action: nil)
    
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
        
        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 12
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mainStack)
        
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        // 1. Stage Card with simulated Dark Menu Bar strip and drop zone
        dropTargetCard.boxType = .custom
        dropTargetCard.borderColor = NSColor.separatorColor.withAlphaComponent(0.3)
        dropTargetCard.borderWidth = 1.0
        dropTargetCard.cornerRadius = 8
        dropTargetCard.fillColor = NSColor.windowBackgroundColor.withAlphaComponent(0.6)
        dropTargetCard.translatesAutoresizingMaskIntoConstraints = false
        mainStack.addArrangedSubview(dropTargetCard)
        dropTargetCard.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true
        
        let cardStack = NSStackView()
        cardStack.orientation = .vertical
        cardStack.alignment = .centerX
        cardStack.spacing = 10
        cardStack.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        dropTargetCard.contentView = cardStack
        
        // Mini simulated macOS menu bar strip
        let simulatedBar = NSBox()
        simulatedBar.boxType = .custom
        simulatedBar.borderColor = NSColor.separatorColor.withAlphaComponent(0.2)
        simulatedBar.borderWidth = 1.0
        simulatedBar.cornerRadius = 6
        simulatedBar.fillColor = NSColor.black.withAlphaComponent(0.25)
        simulatedBar.translatesAutoresizingMaskIntoConstraints = false
        simulatedBar.heightAnchor.constraint(equalToConstant: 34).isActive = true
        
        let barStack = NSStackView()
        barStack.orientation = .horizontal
        barStack.alignment = .centerY
        barStack.spacing = 12
        barStack.edgeInsets = NSEdgeInsets(top: 4, left: 12, bottom: 4, right: 12)
        barStack.translatesAutoresizingMaskIntoConstraints = false
        simulatedBar.contentView = barStack
        
        let barLabel = NSTextField(labelWithString: "Menu Bar Preview:")
        barLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        barLabel.textColor = NSColor.secondaryLabelColor
        barStack.addArrangedSubview(barLabel)
        
        liveContainer.translatesAutoresizingMaskIntoConstraints = false
        barStack.addArrangedSubview(liveContainer)
        
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        barStack.addArrangedSubview(spacer)
        
        cardStack.addArrangedSubview(simulatedBar)
        simulatedBar.widthAnchor.constraint(equalTo: cardStack.widthAnchor).isActive = true
        
        // Drop hint label
        dropHintLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        dropHintLabel.textColor = NSColor.tertiaryLabelColor
        cardStack.addArrangedSubview(dropHintLabel)
        
        // 2. Placement Controls Row
        let placementRow = NSStackView()
        placementRow.orientation = .horizontal
        placementRow.alignment = .centerY
        placementRow.spacing = 10
        placementRow.translatesAutoresizingMaskIntoConstraints = false
        
        placementLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        placementLabel.textColor = NSColor.secondaryLabelColor
        placementRow.addArrangedSubview(placementLabel)
        
        leftBtn.bezelStyle = .rounded
        leftBtn.controlSize = .small
        leftBtn.target = self
        leftBtn.action = #selector(onMoveLeft)
        placementRow.addArrangedSubview(leftBtn)
        
        rightBtn.bezelStyle = .rounded
        rightBtn.controlSize = .small
        rightBtn.target = self
        rightBtn.action = #selector(onMoveRight)
        placementRow.addArrangedSubview(rightBtn)
        
        mainStack.addArrangedSubview(placementRow)
        
        registerForDraggedTypes([WidgetStyleChipView.stylePasteboardType])
        refreshPreview()
    }
    
    public func refreshPreview() {
        liveContainer.subviews.forEach { $0.removeFromSuperview() }
        
        let style = AppPreferences.shared.displayStyle(for: metric)
        let sample = Self.makeSampleMiniView(metric: metric, style: style)
        sample.translatesAutoresizingMaskIntoConstraints = false
        liveContainer.addSubview(sample)
        
        NSLayoutConstraint.activate([
            sample.topAnchor.constraint(equalTo: liveContainer.topAnchor),
            sample.leadingAnchor.constraint(equalTo: liveContainer.leadingAnchor),
            sample.trailingAnchor.constraint(equalTo: liveContainer.trailingAnchor),
            sample.bottomAnchor.constraint(equalTo: liveContainer.bottomAnchor),
            sample.heightAnchor.constraint(equalToConstant: 22)
        ])
        
        // Placement label & button states
        let order = AppPreferences.shared.metricOrder
        if let idx = order.firstIndex(of: metric) {
            placementLabel.stringValue = "Menu Bar Position: #\(idx + 1) of \(order.count)"
            leftBtn.isEnabled = idx > 0
            rightBtn.isEnabled = idx < order.count - 1
        }
    }
    
    @objc private func onMoveLeft() {
        delegate?.singleMetricWidgetPreviewDidRequestMoveLeft(self)
    }
    
    @objc private func onMoveRight() {
        delegate?.singleMetricWidgetPreviewDidRequestMoveRight(self)
    }
    
    // MARK: - Dragging Destination for Styles
    
    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let styleRaw = sender.draggingPasteboard.string(forType: WidgetStyleChipView.stylePasteboardType),
              let _ = MetricDisplayStyle(rawValue: styleRaw) else {
            return []
        }
        dropTargetCard.borderColor = NSColor.controlAccentColor
        dropTargetCard.borderWidth = 2.0
        dropTargetCard.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.12)
        dropHintLabel.stringValue = "Release to apply this style!"
        dropHintLabel.textColor = .controlAccentColor
        return .copy
    }
    
    public override func draggingExited(_ sender: NSDraggingInfo?) {
        resetDropStyles()
    }
    
    public override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return true
    }
    
    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        resetDropStyles()
        guard let styleRaw = sender.draggingPasteboard.string(forType: WidgetStyleChipView.stylePasteboardType),
              let style = MetricDisplayStyle(rawValue: styleRaw) else {
            return false
        }
        delegate?.singleMetricWidgetPreview(self, didDropStyle: style)
        return true
    }
    
    private func resetDropStyles() {
        dropTargetCard.borderColor = NSColor.separatorColor.withAlphaComponent(0.3)
        dropTargetCard.borderWidth = 1.0
        dropTargetCard.fillColor = NSColor.windowBackgroundColor.withAlphaComponent(0.6)
        dropHintLabel.stringValue = "Drag and drop any style card below directly onto this preview to customize it"
        dropHintLabel.textColor = NSColor.tertiaryLabelColor
    }
    
    // MARK: - Static Sample Factory
    
    public static func makeSampleMiniView(metric: MetricType, style: MetricDisplayStyle) -> NSView {
        let prefs = AppPreferences.shared
        let theme = prefs.colorTheme
        
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        
        switch (metric, style) {
        case (.cpu, .barOnly):
            let barHost = MiniCanvasView(drawBlock: { ctx, bounds in
                StatusItemRenderer.drawBarsOnly(
                    in: ctx,
                    rect: bounds,
                    values: [20.0, 45.0, 15.0, 30.0],
                    barCount: 4,
                    primaryColor: theme.primaryColor
                )
            })
            barHost.widthAnchor.constraint(equalToConstant: 20).isActive = true
            barHost.heightAnchor.constraint(equalToConstant: 12).isActive = true
            stack.addArrangedSubview(barHost)
            
        case (.cpu, .circularGauge):
            let gaugeHost = MiniCanvasView(drawBlock: { ctx, bounds in
                StatusItemRenderer.drawCircularGauge(in: ctx, rect: bounds, percentage: 28.0, fillColor: theme.primaryColor)
            })
            gaugeHost.widthAnchor.constraint(equalToConstant: 16).isActive = true
            gaugeHost.heightAnchor.constraint(equalToConstant: 16).isActive = true
            stack.addArrangedSubview(gaugeHost)
            
        case (.cpu, .textOnly):
            let lbl = makeLabel("28%", color: theme.primaryColor)
            stack.addArrangedSubview(lbl)
            
        case (.memory, .multicolorCircle):
            let circleHost = MiniCanvasView(drawBlock: { ctx, bounds in
                let segments: [(fraction: Double, color: NSColor)] = [
                    (0.38, .systemBlue),
                    (0.18, .systemIndigo),
                    (0.12, .systemTeal)
                ]
                StatusItemRenderer.drawMulticolorCircle(in: ctx, rect: bounds, segments: segments, lineWidth: 2.5)
            })
            circleHost.widthAnchor.constraint(equalToConstant: 16).isActive = true
            circleHost.heightAnchor.constraint(equalToConstant: 16).isActive = true
            stack.addArrangedSubview(circleHost)
            
        case (.memory, .barOnly):
            let barHost = MiniCanvasView(drawBlock: { ctx, bounds in
                StatusItemRenderer.drawHorizontalBar(in: ctx, rect: bounds, percentage: 68.0, fillColor: theme.secondaryColor)
            })
            barHost.widthAnchor.constraint(equalToConstant: 20).isActive = true
            barHost.heightAnchor.constraint(equalToConstant: 7).isActive = true
            stack.addArrangedSubview(barHost)
            
        case (.memory, .circularGauge):
            let gaugeHost = MiniCanvasView(drawBlock: { ctx, bounds in
                StatusItemRenderer.drawCircularGauge(in: ctx, rect: bounds, percentage: 68.0, fillColor: theme.secondaryColor)
            })
            gaugeHost.widthAnchor.constraint(equalToConstant: 16).isActive = true
            gaugeHost.heightAnchor.constraint(equalToConstant: 16).isActive = true
            stack.addArrangedSubview(gaugeHost)
            
        case (.disk, .barOnly):
            let barHost = MiniCanvasView(drawBlock: { ctx, bounds in
                StatusItemRenderer.drawHorizontalBar(in: ctx, rect: bounds, percentage: 62.0, fillColor: .systemPurple)
            })
            barHost.widthAnchor.constraint(equalToConstant: 20).isActive = true
            barHost.heightAnchor.constraint(equalToConstant: 7).isActive = true
            stack.addArrangedSubview(barHost)
            
        case (.disk, .circularGauge):
            let gaugeHost = MiniCanvasView(drawBlock: { ctx, bounds in
                StatusItemRenderer.drawCircularGauge(in: ctx, rect: bounds, percentage: 62.0, fillColor: .systemPurple)
            })
            gaugeHost.widthAnchor.constraint(equalToConstant: 16).isActive = true
            gaugeHost.heightAnchor.constraint(equalToConstant: 16).isActive = true
            stack.addArrangedSubview(gaugeHost)
            
        case (.battery, .barOnly):
            let icon = NSImage(systemSymbolName: "battery.75", accessibilityDescription: nil)
            let iv = NSImageView(image: icon ?? NSImage())
            iv.contentTintColor = NSColor.headerTextColor
            iv.widthAnchor.constraint(equalToConstant: 18).isActive = true
            iv.heightAnchor.constraint(equalToConstant: 14).isActive = true
            stack.addArrangedSubview(iv)
            
        case (.temperatures, .circularGauge):
            let gaugeHost = MiniCanvasView(drawBlock: { ctx, bounds in
                StatusItemRenderer.drawCircularGauge(in: ctx, rect: bounds, percentage: 48.0, fillColor: .systemOrange)
            })
            gaugeHost.widthAnchor.constraint(equalToConstant: 16).isActive = true
            gaugeHost.heightAnchor.constraint(equalToConstant: 16).isActive = true
            stack.addArrangedSubview(gaugeHost)
            
        case (.weather, .barOnly):
            let icon = NSImage(systemSymbolName: "cloud.sun.fill", accessibilityDescription: nil)
            let iv = NSImageView(image: icon ?? NSImage())
            iv.contentTintColor = .systemOrange
            iv.imageScaling = .scaleProportionallyUpOrDown
            iv.widthAnchor.constraint(equalToConstant: 16).isActive = true
            iv.heightAnchor.constraint(equalToConstant: 16).isActive = true
            stack.addArrangedSubview(iv)
            
        case (.weather, .circularGauge):
            let gaugeHost = MiniCanvasView(drawBlock: { ctx, bounds in
                StatusItemRenderer.drawCircularGauge(in: ctx, rect: bounds, percentage: 65.0, fillColor: .systemOrange)
            })
            gaugeHost.widthAnchor.constraint(equalToConstant: 16).isActive = true
            gaugeHost.heightAnchor.constraint(equalToConstant: 16).isActive = true
            stack.addArrangedSubview(gaugeHost)
            
        default:
            let text = sampleTextFor(metric: metric)
            let label = makeLabel(text, color: theme.primaryColor)
            stack.addArrangedSubview(label)
            
            if style != .textOnly, let icon = NSImage(systemSymbolName: metric.iconSymbolName, accessibilityDescription: nil) {
                let iconView = NSImageView(image: icon)
                iconView.contentTintColor = theme.secondaryColor
                iconView.imageScaling = .scaleProportionallyUpOrDown
                iconView.widthAnchor.constraint(equalToConstant: 13).isActive = true
                iconView.heightAnchor.constraint(equalToConstant: 13).isActive = true
                stack.addArrangedSubview(iconView)
            }
        }
        
        return container
    }
    
    private static func makeLabel(_ string: String, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: string)
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        label.textColor = color
        return label
    }
    
    private static func sampleTextFor(metric: MetricType) -> String {
        switch metric {
        case .cpu: return "28%"
        case .memory:
            switch AppPreferences.shared.memoryDisplayMode {
            case .percentage: return "48%"
            case .usedAmount: return "7.8G"
            case .pressure: return "NORM"
            }
        case .disk: return "68%"
        case .network: return "1.2M/s"
        case .battery: return "95%"
        case .temperatures:
            return AppPreferences.shared.temperatureUnit == .fahrenheit ? "118°F" : "48°C"
        case .displays: return "2"
        case .weather:
            return AppPreferences.shared.temperatureUnit == .fahrenheit ? "72°F" : "22°C"
        }
    }
}

private final class MiniCanvasView: NSView {
    private let drawBlock: (CGContext, CGRect) -> Void
    
    init(drawBlock: @escaping (CGContext, CGRect) -> Void) {
        self.drawBlock = drawBlock
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        drawBlock(ctx, bounds)
    }
}
