import AppKit

public final class PopoverViewController: NSViewController {
    private let scrollView = NSScrollView()
    private let contentStack = FlippedStackView()
    
    private let graphContainerView = CPUGraphView()
    private let cpuDetailView = CPUDetailView()
    private let memoryDetailView = MemoryDetailView()
    
    public override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 420))
        self.view = root
        setupLayout()
    }
    
    public override func viewWillAppear() {
        super.viewWillAppear()
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
    
    private func setupLayout() {
        view.wantsLayer = true
        
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        
        contentStack.orientation = .vertical
        contentStack.alignment = .width
        contentStack.spacing = 16
        contentStack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        
        let clipView = NSClipView()
        clipView.drawsBackground = false
        clipView.documentView = contentStack
        scrollView.contentView = clipView
        
        // Add sections
        let graphSection = createSectionView(title: "CPU HISTORY (60s)", contentView: graphContainerView)
        graphContainerView.heightAnchor.constraint(equalToConstant: 90).isActive = true
        
        contentStack.addArrangedSubview(graphSection)
        contentStack.addArrangedSubview(createSeparator())
        contentStack.addArrangedSubview(cpuDetailView)
        contentStack.addArrangedSubview(createSeparator())
        contentStack.addArrangedSubview(memoryDetailView)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])
    }
    
    private func createSeparator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        return separator
    }
    
    private func createSectionView(title: String, contentView: NSView) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        label.textColor = NSColor.secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        
        contentView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(contentView)
        
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            
            contentView.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 6),
            contentView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        
        return container
    }
    
    public func updateMetrics(cpu: CPUStats, memory: MemoryStats) {
        graphContainerView.pushCPUValue(cpu.totalUsage)
        cpuDetailView.update(stats: cpu)
        memoryDetailView.update(stats: memory)
    }
}

public final class CPUGraphView: NSView {
    private let renderer = CPUGraphRenderer()
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }
    
    public func pushCPUValue(_ value: Double) {
        renderer.push(value: value)
        let now = ProcessInfo.processInfo.systemUptime
        if renderer.shouldRender(now: now) {
            needsDisplay = true
        }
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        renderer.render(in: context, rect: bounds)
    }
}
