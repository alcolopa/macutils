import AppKit

/// A rounded settings group: optional heading, then its content stacked full width.
final class SettingsCardView: NSView {
    private let inset: CGFloat = 20
    private var lastBottom: NSLayoutYAxisAnchor
    private let bottomPadding: CGFloat = 16
    private var bottomConstraint: NSLayoutConstraint?
    
    init(title: String?) {
        lastBottom = NSLayoutYAxisAnchor()
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        lastBottom = topAnchor
        var firstGap: CGFloat = 16
        if let title {
            let label = NSTextField(labelWithString: title)
            label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            label.textColor = .labelColor
            label.alignment = .left
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: topAnchor, constant: 16),
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
                label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -inset)
            ])
            lastBottom = label.bottomAnchor
            firstGap = 14
        }
        self.firstGap = firstGap
    }
    
    private var firstGap: CGFloat = 16
    private var isFirst = true
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    func add(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        bottomConstraint?.isActive = false
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: lastBottom, constant: isFirst ? firstGap : 14),
            view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            view.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset)
        ])
        isFirst = false
        lastBottom = view.bottomAnchor
        bottomConstraint = bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: bottomPadding)
        bottomConstraint?.isActive = true
    }
    
    override func updateLayer() {
        layer?.cornerRadius = 14
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.055).cgColor
        }
    }
    
    override var wantsUpdateLayer: Bool { true }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
}

/// Title and explanation on the left, control on the right.
final class ToggleRowView: NSView {
    init(title: String, detail: String?, control: NSView) {
        super.init(frame: .zero)
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.alignment = .left
        for v in [titleLabel, control] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.init(250), for: .horizontal)
        
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: control.leadingAnchor, constant: -20),
            control.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        if let detail {
            let d = NSTextField(wrappingLabelWithString: detail)
            d.font = NSFont.systemFont(ofSize: 11.5)
            d.textColor = .secondaryLabelColor
            d.isSelectable = false
            d.alignment = .left
            d.translatesAutoresizingMaskIntoConstraints = false
            addSubview(d)
            titleLabel.topAnchor.constraint(equalTo: topAnchor).isActive = true
            NSLayoutConstraint.activate([
                d.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
                d.leadingAnchor.constraint(equalTo: leadingAnchor),
                d.trailingAnchor.constraint(lessThanOrEqualTo: control.leadingAnchor, constant: -20),
                d.bottomAnchor.constraint(equalTo: bottomAnchor),
                control.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
            d.preferredMaxLayoutWidth = 430
        } else {
            NSLayoutConstraint.activate([
                titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                control.topAnchor.constraint(equalTo: topAnchor),
                control.bottomAnchor.constraint(equalTo: bottomAnchor),
                heightAnchor.constraint(greaterThanOrEqualToConstant: 26)
            ])
        }
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Small layout helpers so every preferences page uses the same card / form-row structure.
@MainActor
enum SettingsLayout {
    static let labelWidth: CGFloat = 160
    
    static func card(title: String?, _ views: [NSView]) -> SettingsCardView {
        let card = SettingsCardView(title: title)
        for v in views { card.add(v) }
        return card
    }
    
    static func paragraph(_ text: String, small: Bool = false) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = NSFont.systemFont(ofSize: small ? 11.5 : 12.5)
        label.textColor = small ? .tertiaryLabelColor : .secondaryLabelColor
        label.isSelectable = false
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
    
    /// "Label ........ [control]" row with a fixed label column so controls line up.
    static func row(_ title: String, _ control: NSView, trailing: NSView? = nil) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 13)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: labelWidth).isActive = true
        
        var views: [NSView] = [label, control]
        if let trailing { views.append(trailing) }
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 16
        return row
    }
    
    /// System Settings style row: title and explanation on the left, control on the right.
    static func toggleRow(_ title: String, detail: String? = nil, control: NSView) -> NSView {
        ToggleRowView(title: title, detail: detail, control: control)
    }
    
    static func divider() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        return box
    }
    
    static func spacer() -> NSView {
        let v = NSView()
        v.setContentHuggingPriority(.init(1), for: .horizontal)
        return v
    }
}
