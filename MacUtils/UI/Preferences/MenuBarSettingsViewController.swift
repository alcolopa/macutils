import AppKit

/// A single place to inspect and arrange all of MacUtils' menu bar items.
@MainActor
final class MenuBarSettingsViewController: SettingsPageViewController {
    private let prefs = AppPreferences.shared
    private let preview = MenuBarLivePreviewView()
    private let groups = NSStackView()
    private let monitors = NSStackView()
    private var previewWidth: NSLayoutConstraint?

    override var pageTitle: String { "Menu Bar" }
    override var pageSubtitle: String { "See your setup and arrange everything in one place. Changes apply immediately." }

    override func buildCards() -> [NSView] {
        observe(AppPreferences.didChange)
        observe(CaffeinateManager.didChange)
        for stack in [groups, monitors] {
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 12
        }

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = preview
        scroll.heightAnchor.constraint(equalToConstant: 60).isActive = true
        previewWidth = preview.widthAnchor.constraint(equalToConstant: 600)
        previewWidth?.isActive = true
        preview.heightAnchor.constraint(equalToConstant: 40).isActive = true

        return [
            SettingsLayout.card(title: "Your MacUtils menu bar", [
                scroll,
                SettingsLayout.paragraph("Sample readings with your current styles and icons. Drag monitors to reorder them. Scroll sideways to see a wide setup. Other apps’ menu bar items are not included.")
            ]),
            SettingsLayout.card(title: "Group order · left to right", [groups]),
            SettingsLayout.card(title: "Monitors · left to right", [monitors])
        ]
    }

    override func refresh() {
        guard isViewLoaded else { return }
        preview.refreshPreview()
        previewWidth?.constant = max(600, preview.contentWidth)
        for stack in [groups, monitors] {
            stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        }
        for (index, block) in prefs.barBlockOrder.enumerated() {
            let title: String
            switch block {
            case .clipboard: title = "Clipboard"
            case .caffeinate: title = "Caffeinate"
            case .monitors: title = "System monitors"
            }
            let controls = moveControl(index: index, count: prefs.barBlockOrder.count, action: #selector(moveGroup(_:)))
            controls.identifier = .init(block.rawValue)
            addRow(title, controls: [controls], to: groups)
        }
        // Utility visibility and appearance stay accessible even when their icons are hidden.
        for page in [PreferencesPage.clipboard, .caffeinate] {
            let toggle = makeSwitch(on: page == .clipboard ? prefs.clipboardEnabled && prefs.showClipboardIcon : prefs.showCaffeinate,
                                    action: #selector(toggleUtility(_:)))
            toggle.tag = page.rawValue
            addRow(page.title, controls: [toggle, settingsButton(page)], to: groups)
        }
        for (index, metric) in prefs.metricOrder.enumerated() {
            let toggle = makeSwitch(on: prefs.isMetricVisible(metric), action: #selector(toggleMonitor(_:)))
            toggle.identifier = .init(metric.rawValue)
            let move = moveControl(index: index, count: prefs.metricOrder.count, action: #selector(moveMonitor(_:)))
            move.identifier = .init(metric.rawValue)
            let page = PreferencesPage.allCases.first { $0.metric == metric } ?? .cpu
            addRow(page.title, controls: [toggle, move, settingsButton(page)], to: monitors)
        }
    }

    private func addRow(_ title: String, controls: [NSView], to stack: NSStackView) {
        let control = NSStackView(views: controls)
        control.spacing = 8
        let row = SettingsLayout.toggleRow(title, control: control)
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func moveControl(index: Int, count: Int, action: Selector) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: ["←", "→"], trackingMode: .momentary, target: self, action: action)
        control.setEnabled(index > 0, forSegment: 0)
        control.setEnabled(index < count - 1, forSegment: 1)
        control.toolTip = "Move left or right"
        control.setAccessibilityLabel("Move left or right")
        return control
    }

    private func settingsButton(_ page: PreferencesPage) -> NSButton {
        let button = makeButton("Edit…", action: #selector(openSettings(_:)))
        button.tag = page.rawValue
        button.setAccessibilityLabel("Edit \(page.title) settings")
        return button
    }

    @objc private func moveGroup(_ sender: NSSegmentedControl) {
        guard let raw = sender.identifier?.rawValue, let block = BarBlock(rawValue: raw) else { return }
        prefs.moveBarBlock(block, by: sender.selectedSegment == 0 ? -1 : 1)
    }

    @objc private func moveMonitor(_ sender: NSSegmentedControl) {
        guard let raw = sender.identifier?.rawValue, let metric = MetricType(rawValue: raw),
              let index = prefs.metricOrder.firstIndex(of: metric) else { return }
        prefs.moveMetric(from: index, to: index + (sender.selectedSegment == 0 ? -1 : 1))
    }

    @objc private func toggleMonitor(_ sender: NSSwitch) {
        guard let raw = sender.identifier?.rawValue, let metric = MetricType(rawValue: raw) else { return }
        prefs.setMetricVisible(metric, visible: sender.state == .on)
    }

    @objc private func toggleUtility(_ sender: NSSwitch) {
        if sender.tag == PreferencesPage.clipboard.rawValue {
            if sender.state == .on { prefs.clipboardEnabled = true }
            prefs.showClipboardIcon = sender.state == .on
        } else {
            prefs.showCaffeinate = sender.state == .on
        }
    }

    @objc private func openSettings(_ sender: NSButton) {
        guard let page = PreferencesPage(rawValue: sender.tag) else { return }
        PreferencesWindowController.shared.showPreferences(selecting: page)
    }
}
