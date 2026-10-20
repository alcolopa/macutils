import AppKit

enum PreferencesPage: Int, CaseIterable {
    case general, menuBar, clipboard, caffeinate, cpu, memory, disk, network, temperatures, weather
    
    var metric: MetricType? {
        switch self {
        case .cpu: return .cpu
        case .memory: return .memory
        case .disk: return .disk
        case .network: return .network
        case .temperatures: return .temperatures
        case .weather: return .weather
        default: return nil
        }
    }
    
    var title: String {
        switch self {
        case .general: return "General"
        case .menuBar: return "Menu Bar"
        case .clipboard: return "Clipboard"
        case .caffeinate: return "Caffeinate"
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .disk: return "Disk"
        case .network: return "Network"
        case .temperatures: return "Temperatures"
        case .weather: return "Weather"
        }
    }
    
    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .menuBar: return "menubar.rectangle"
        case .clipboard: return "doc.on.clipboard.fill"
        case .caffeinate: return "cup.and.saucer.fill"
        default: return metric?.iconSymbolName ?? "circle"
        }
    }
    
    var color: NSColor {
        switch self {
        case .general: return .systemGray
        case .menuBar: return .systemIndigo
        case .clipboard: return .systemBlue
        case .caffeinate: return .systemOrange
        case .cpu: return .systemRed
        case .memory: return .systemPurple
        case .disk: return .systemTeal
        case .network: return .systemGreen
        case .temperatures: return .systemPink
        case .weather: return .systemCyan
        }
    }
    
    @MainActor
    func makeViewController() -> NSViewController {
        switch self {
        case .general: return GeneralSettingsViewController()
        case .menuBar: return MenuBarSettingsViewController()
        case .clipboard: return ClipboardSettingsViewController()
        case .caffeinate: return CaffeinateSettingsViewController()
        default: return MetricSettingsViewController(metric: metric ?? .cpu)
        }
    }
}

/// Sidebar + detail layout, like System Settings.
@MainActor
final class PreferencesSplitViewController: NSSplitViewController {
    private let sidebar = PreferencesSidebarViewController()
    private let detail = PreferencesDetailViewController()
    
    // Pages must never drive the window size.
    override var preferredContentSize: NSSize { get { NSSize(width: 900, height: 680) } set {} }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 210
        sidebarItem.maximumThickness = 230
        sidebarItem.canCollapse = false
        let detailItem = NSSplitViewItem(viewController: detail)
        detailItem.minimumThickness = 560
        addSplitViewItem(sidebarItem)
        addSplitViewItem(detailItem)
        sidebar.onSelect = { [weak self] page in self?.detail.show(page) }
        select(.general)
    }
    
    func select(_ page: PreferencesPage) {
        sidebar.select(page)
        detail.show(page)
    }
}

@MainActor
final class PreferencesDetailViewController: NSViewController {
    private var cache: [PreferencesPage: NSViewController] = [:]
    private var current: NSViewController?
    
    override var preferredContentSize: NSSize { get { NSSize(width: 670, height: 680) } set {} }
    
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 680, height: 640))
    }
    
    func show(_ page: PreferencesPage) {
        let vc = cache[page] ?? page.makeViewController()
        cache[page] = vc
        guard vc !== current else { return }
        current?.view.removeFromSuperview()
        current?.removeFromParent()
        addChild(vc)
        vc.view.frame = view.bounds
        vc.view.autoresizingMask = [.width, .height]
        view.addSubview(vc.view)
        current = vc
    }
}

@MainActor
final class PreferencesSidebarViewController: NSViewController, @preconcurrency NSTableViewDataSource, @preconcurrency NSTableViewDelegate {
    private enum Row {
        case header(String)
        case page(PreferencesPage)
    }
    
    private let rows: [Row] = [
        .page(.general), .page(.menuBar), .page(.clipboard), .page(.caffeinate),
        .header("System Monitor"),
        .page(.cpu), .page(.memory), .page(.disk), .page(.network), .page(.temperatures), .page(.weather)
    ]
    private let tableView = NSTableView()
    var onSelect: ((PreferencesPage) -> Void)?
    
    override func loadView() {
        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 210, height: 640))
        effect.material = .sidebar
        effect.blendingMode = .behindWindow
        effect.state = .followsWindowActiveState
        
        let scroll = NSScrollView(frame: effect.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 52, left: 0, bottom: 0, right: 0)
        tableView.headerView = nil
        tableView.style = .sourceList
        tableView.backgroundColor = .clear
        tableView.rowSizeStyle = .default
        tableView.dataSource = self
        tableView.delegate = self
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        scroll.documentView = tableView
        effect.addSubview(scroll)
        view = effect
        tableView.reloadData()
    }
    
    override func viewDidLayout() {
        super.viewDidLayout()
        if let column = tableView.tableColumns.first {
            column.width = max(120, view.bounds.width - 16)
        }
    }
    
    func select(_ page: PreferencesPage) {
        guard let index = rows.firstIndex(where: { if case .page(let p) = $0 { return p == page } else { return false } }) else { return }
        tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
    }
    
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    
    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        if case .header = rows[row] { return true }
        return false
    }
    
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if case .page = rows[row] { return true }
        return false
    }
    
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if case .header = rows[row] { return 34 }
        return 36
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .header(let title):
            let label = NSTextField(labelWithString: title)
            label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
            label.textColor = .secondaryLabelColor
            let cell = NSTableCellView()
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                label.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -2)
            ])
            return cell
        case .page(let page):
            let box = NSView()
            box.wantsLayer = true
            box.layer?.cornerRadius = 7
            box.layer?.backgroundColor = page.color.cgColor
            box.translatesAutoresizingMaskIntoConstraints = false
            let icon = NSImageView(image: NSImage(systemSymbolName: page.symbol, accessibilityDescription: nil) ?? NSImage())
            icon.contentTintColor = .white
            icon.symbolConfiguration = .init(pointSize: 12, weight: .semibold)
            icon.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(icon)
            let label = NSTextField(labelWithString: page.title)
            label.font = NSFont.systemFont(ofSize: 14, weight: .medium)
            label.translatesAutoresizingMaskIntoConstraints = false
            let cell = NSTableCellView()
            cell.addSubview(box)
            cell.addSubview(label)
            label.lineBreakMode = .byTruncatingTail
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            NSLayoutConstraint.activate([
                label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -6),
                box.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                box.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                box.widthAnchor.constraint(equalToConstant: 26),
                box.heightAnchor.constraint(equalToConstant: 26),
                icon.centerXAnchor.constraint(equalTo: box.centerXAnchor),
                icon.centerYAnchor.constraint(equalTo: box.centerYAnchor),
                label.leadingAnchor.constraint(equalTo: box.trailingAnchor, constant: 10),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return cell
        }
    }
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0, case .page(let page) = rows[row] else { return }
        onSelect?(page)
    }
}
