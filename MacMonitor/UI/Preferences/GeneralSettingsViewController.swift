import AppKit
import ServiceManagement

@MainActor
public final class GeneralSettingsViewController: NSViewController, @preconcurrency NSTableViewDataSource, @preconcurrency NSTableViewDelegate {
    private static let dragType = NSPasteboard.PasteboardType("com.macmonitor.tablemetricdrag")
    
    private let prefs = AppPreferences.shared
    private let livePreview = MenuBarLivePreviewView()
    private let tableView = NSTableView()
    private lazy var orderedMetrics: [MetricType] = prefs.metricOrder
    
    private let paddingSlider = NSSlider(value: 0, minValue: 0, maxValue: 12, target: nil, action: nil)
    private let paddingLabel = NSTextField(labelWithString: "0 pt")
    
    private let launchAtLoginCheck = NSButton(checkboxWithTitle: "Launch MacMonitor at login", target: nil, action: nil)
    
    private let themePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let intervalSlider = NSSlider(value: 1.5, minValue: 0.25, maxValue: 5.0, target: nil, action: nil)
    private let intervalLabel = NSTextField(labelWithString: "1.5s")
    
    public override func loadView() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 620, height: 560))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        
        let contentView = FlippedView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        
        let clipView = NSClipView()
        clipView.drawsBackground = false
        clipView.documentView = contentView
        scrollView.contentView = clipView
        
        self.view = scrollView
        setupUI(in: contentView, parentScrollView: scrollView)
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        orderedMetrics = prefs.metricOrder
        tableView.reloadData()
    }
    
    private func setupUI(in container: NSView, parentScrollView: NSScrollView) {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 24
        stack.edgeInsets = NSEdgeInsets(top: 28, left: 32, bottom: 36, right: 32)
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        
        // 1. Live preview
        stack.addArrangedSubview(SettingsLayout.card(title: "Menu Bar Preview", [
            SettingsLayout.paragraph("Drag widgets left or right to reorder them."),
            livePreview
        ]))
        
        // 2. Order & visibility
        let tableScroll = NSScrollView()
        tableScroll.hasVerticalScroller = false
        tableScroll.drawsBackground = false
        tableScroll.borderType = .noBorder
        tableScroll.translatesAutoresizingMaskIntoConstraints = false
        tableScroll.heightAnchor.constraint(equalToConstant: CGFloat(MetricType.allCases.count) * 34).isActive = true
        
        tableView.headerView = nil
        tableView.rowHeight = 34
        tableView.backgroundColor = .clear
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.style = .plain
        tableView.dataSource = self
        tableView.delegate = self
        tableView.registerForDraggedTypes([Self.dragType])
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("MetricCol"))
        col.title = "Metric"
        col.width = 300
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)
        tableScroll.documentView = tableView
        
        let moveUpBtn = NSButton(title: "Move Up", target: self, action: #selector(onMoveUp))
        let moveDownBtn = NSButton(title: "Move Down", target: self, action: #selector(onMoveDown))
        let resetBtn = NSButton(title: "Reset Order", target: self, action: #selector(onResetOrder))
        for b in [moveUpBtn, moveDownBtn, resetBtn] {
            b.bezelStyle = .rounded
            b.controlSize = .small
        }
        let btnRow = NSStackView(views: [moveUpBtn, moveDownBtn, SettingsLayout.spacer(), resetBtn])
        btnRow.orientation = .horizontal
        btnRow.spacing = 8
        
        stack.addArrangedSubview(SettingsLayout.card(title: "Widgets", [
            SettingsLayout.paragraph("Tick a widget to show it in the menu bar. Drag rows to reorder, or select one and use the buttons."),
            tableScroll,
            btnRow
        ]))
        
        // 3. All-widget appearance shortcuts
        paddingSlider.minValue = 0
        paddingSlider.maxValue = 12
        paddingSlider.doubleValue = prefs.barOptions(for: .cpu).padding
        paddingSlider.target = self
        paddingSlider.action = #selector(onPaddingChanged)
        paddingLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        paddingLabel.stringValue = "\(Int(paddingSlider.doubleValue)) pt"
        paddingLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true
        
        stack.addArrangedSubview(SettingsLayout.card(title: "Menu Bar Spacing", [
            SettingsLayout.paragraph("Applies to every widget. Icons, labels and padding can be set per widget from its own tab."),
            SettingsLayout.row("Widget padding", paddingSlider, trailing: paddingLabel)
        ]))
        
        // 4. Theme & polling
        themePopup.removeAllItems()
        for theme in ColorTheme.allCases { themePopup.addItem(withTitle: theme.rawValue) }
        themePopup.selectItem(withTitle: prefs.colorTheme.rawValue)
        themePopup.target = self
        themePopup.action = #selector(onThemeChanged)
        
        intervalSlider.doubleValue = prefs.passiveInterval
        intervalSlider.target = self
        intervalSlider.action = #selector(onIntervalChanged)
        intervalLabel.stringValue = String(format: "%.1fs", prefs.passiveInterval)
        intervalLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        intervalLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true
        
        launchAtLoginCheck.target = self
        launchAtLoginCheck.action = #selector(onLaunchAtLoginToggled)
        launchAtLoginCheck.state = SMAppService.mainApp.status == .enabled ? .on : .off
        
        stack.addArrangedSubview(SettingsLayout.card(title: "Startup", [
            SettingsLayout.row("Login item", launchAtLoginCheck),
            SettingsLayout.paragraph("Runs MacMonitor in the background whenever you log in. Requires running the built MacMonitor.app (scripts/build_app.sh), ideally from /Applications.", small: true)
        ]))
        
        stack.addArrangedSubview(SettingsLayout.card(title: "Appearance & Updates", [
            SettingsLayout.row("Colour theme", themePopup),
            SettingsLayout.row("Update frequency", intervalSlider, trailing: intervalLabel),
            SettingsLayout.paragraph("Sampling speeds up to 0.5 s while a panel is open, and idles at this rate otherwise.", small: true)
        ]))
        
        // Every card spans the full page width (minus side insets) so edges line up
        for card in stack.arrangedSubviews {
            card.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -(stack.edgeInsets.left + stack.edgeInsets.right)).isActive = true
        }
        
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            
            container.topAnchor.constraint(equalTo: parentScrollView.topAnchor),
            container.leadingAnchor.constraint(equalTo: parentScrollView.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: parentScrollView.trailingAnchor),
            container.widthAnchor.constraint(equalTo: parentScrollView.widthAnchor)
        ])
    }
    
    @objc private func onLaunchAtLoginToggled() {
        do {
            if launchAtLoginCheck.state == .on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn't change login item"
            alert.runModal()
        }
        launchAtLoginCheck.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
    
    @objc private func onPaddingChanged() {
        let v = round(paddingSlider.doubleValue)
        paddingLabel.stringValue = "\(Int(v)) pt"
        for m in MetricType.allCases {
            var o = prefs.barOptions(for: m); o.padding = v; prefs.setBarOptions(o, for: m)
        }
    }
    
    // MARK: - NSTableViewDataSource & Delegate
    
    public func numberOfRows(in tableView: NSTableView) -> Int {
        return orderedMetrics.count
    }
    
    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < orderedMetrics.count else { return nil }
        let metric = orderedMetrics[row]
        
        let cellView = NSTableCellView()
        let cell = NSStackView()
        cell.orientation = .horizontal
        cell.spacing = 8
        cell.alignment = .centerY
        cell.translatesAutoresizingMaskIntoConstraints = false
        cellView.addSubview(cell)
        NSLayoutConstraint.activate([
            cell.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
            cell.trailingAnchor.constraint(lessThanOrEqualTo: cellView.trailingAnchor),
            cell.centerYAnchor.constraint(equalTo: cellView.centerYAnchor)
        ])
        
        let check = NSButton(checkboxWithTitle: "", target: self, action: #selector(onMetricToggled(_:)))
        check.tag = row
        check.state = prefs.isMetricVisible(metric) ? .on : .off
        cell.addArrangedSubview(check)
        
        if let icon = NSImage(systemSymbolName: metric.iconSymbolName, accessibilityDescription: nil) {
            let iv = NSImageView(image: icon)
            iv.contentTintColor = prefs.colorTheme.primaryColor
            iv.imageScaling = .scaleProportionallyUpOrDown
            iv.widthAnchor.constraint(equalToConstant: 14).isActive = true
            iv.heightAnchor.constraint(equalToConstant: 14).isActive = true
            cell.addArrangedSubview(iv)
        }
        
        let label = NSTextField(labelWithString: metric.displayName)
        label.font = NSFont.systemFont(ofSize: 12)
        cell.addArrangedSubview(label)
        
        return cellView
    }
    
    // MARK: - Table View Drag and Drop Reordering
    
    public func tableView(_ tableView: NSTableView, writeRowsWith rowIndexes: IndexSet, to pboard: NSPasteboard) -> Bool {
        guard let row = rowIndexes.first else { return false }
        let pbItem = NSPasteboardItem()
        pbItem.setString(String(row), forType: Self.dragType)
        pboard.writeObjects([pbItem])
        return true
    }
    
    public func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard dropOperation == .above else { return [] }
        return .move
    }
    
    public func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let item = info.draggingPasteboard.pasteboardItems?.first,
              let str = item.string(forType: Self.dragType),
              let sourceRow = Int(str),
              sourceRow >= 0 && sourceRow < orderedMetrics.count else {
            return false
        }
        
        let targetRow = row > sourceRow ? row - 1 : row
        let moved = orderedMetrics.remove(at: sourceRow)
        orderedMetrics.insert(moved, at: targetRow)
        prefs.metricOrder = orderedMetrics
        
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: targetRow), byExtendingSelection: false)
        livePreview.refreshPreview()
        return true
    }
    
    @objc private func onMetricToggled(_ sender: NSButton) {
        let row = sender.tag
        guard row < orderedMetrics.count else { return }
        let metric = orderedMetrics[row]
        prefs.setMetricVisible(metric, visible: sender.state == .on)
        livePreview.refreshPreview()
    }
    
    @objc private func onMoveUp() {
        let sel = tableView.selectedRow
        guard sel > 0 && sel < orderedMetrics.count else { return }
        orderedMetrics.swapAt(sel, sel - 1)
        prefs.metricOrder = orderedMetrics
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: sel - 1), byExtendingSelection: false)
        livePreview.refreshPreview()
    }
    
    @objc private func onMoveDown() {
        let sel = tableView.selectedRow
        guard sel >= 0 && sel < orderedMetrics.count - 1 else { return }
        orderedMetrics.swapAt(sel, sel + 1)
        prefs.metricOrder = orderedMetrics
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: sel + 1), byExtendingSelection: false)
        livePreview.refreshPreview()
    }
    
    @objc private func onResetOrder() {
        orderedMetrics = MetricType.allCases
        prefs.metricOrder = orderedMetrics
        tableView.reloadData()
        livePreview.refreshPreview()
    }
    
    @objc private func onThemeChanged() {
        guard let title = themePopup.titleOfSelectedItem,
              let theme = ColorTheme(rawValue: title) else { return }
        prefs.colorTheme = theme
        tableView.reloadData()
        livePreview.refreshPreview()
    }
    
    @objc private func onIntervalChanged() {
        prefs.passiveInterval = intervalSlider.doubleValue
        intervalLabel.stringValue = String(format: "%.1fs", intervalSlider.doubleValue)
    }
}
