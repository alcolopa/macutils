import AppKit

/// Scrollable preferences page built from a vertical stack of cards.
@MainActor
class SettingsPageViewController: NSViewController {
    /// Large heading and one-line description shown above the cards.
    var pageTitle: String { "" }
    var pageSubtitle: String { "" }
    /// Subclasses return the cards to show, top to bottom.
    func buildCards() -> [NSView] { [] }
    /// Called each time the page appears so live state (permissions, counts) is fresh.
    func refresh() {}
    
    override func loadView() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 680, height: 640))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        
        let contentView = FlippedView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        let clipView = NSClipView()
        clipView.drawsBackground = false
        clipView.documentView = contentView
        scrollView.contentView = clipView
        view = scrollView
        
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.edgeInsets = NSEdgeInsets(top: 52, left: 32, bottom: 36, right: 32)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        if !pageTitle.isEmpty {
            let title = NSTextField(labelWithString: pageTitle)
            title.font = NSFont.systemFont(ofSize: 26, weight: .bold)
            let sub = NSTextField(wrappingLabelWithString: pageSubtitle)
            sub.font = NSFont.systemFont(ofSize: 13)
            sub.textColor = .secondaryLabelColor
            sub.isSelectable = false
            let header = NSStackView(views: [title, sub])
            header.orientation = .vertical
            header.alignment = .leading
            header.spacing = 4
            stack.addArrangedSubview(header)
            stack.setCustomSpacing(20, after: header)
        }
        for card in buildCards() { stack.addArrangedSubview(card) }
        for card in stack.arrangedSubviews {
            card.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -(stack.edgeInsets.left + stack.edgeInsets.right)).isActive = true
        }
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])
        refresh()
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
        refresh()
    }
    
    // MARK: - Control helpers
    
    func makeSwitch(on: Bool, action: Selector) -> NSSwitch {
        let s = NSSwitch()
        s.state = on ? .on : .off
        s.target = self
        s.action = action
        return s
    }
    
    func makeButton(_ title: String, action: Selector, primary: Bool = false) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        if primary { b.keyEquivalent = "" ; b.bezelColor = .controlAccentColor }
        return b
    }
    
    func observe(_ name: Notification.Name) {
        NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }
    
    /// A small keyboard-key style label, e.g. "⌘".
    func keyCap(_ text: String) -> NSView {
        let box = NSView()
        box.wantsLayer = true
        box.layer?.cornerRadius = 7
        box.layer?.borderWidth = 1
        box.layer?.borderColor = NSColor.separatorColor.cgColor
        box.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(label)
        box.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            box.widthAnchor.constraint(equalToConstant: 40),
            box.heightAnchor.constraint(equalToConstant: 34),
            label.centerXAnchor.constraint(equalTo: box.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: box.centerYAnchor)
        ])
        return box
    }
}
