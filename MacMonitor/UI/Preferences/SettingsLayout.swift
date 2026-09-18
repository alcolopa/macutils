import AppKit

/// Small layout helpers so every preferences page uses the same card / form-row structure.
@MainActor
enum SettingsLayout {
    static let labelWidth: CGFloat = 160
    
    static func card(title: String, _ views: [NSView]) -> MetricCardView {
        let card = MetricCardView(title: title, contentInsets: NSEdgeInsets(top: 18, left: 20, bottom: 20, right: 20))
        card.setContentSpacing(16)
        for v in views { card.addContentSubview(v) }
        return card
    }
    
    static func paragraph(_ text: String, small: Bool = false) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = NSFont.systemFont(ofSize: small ? 11 : 12)
        label.textColor = small ? .tertiaryLabelColor : .secondaryLabelColor
        label.isSelectable = false
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
    
    /// "Label ........ [control]" row with a fixed label column so controls line up.
    static func row(_ title: String, _ control: NSView, trailing: NSView? = nil) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 12)
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
    
    static func spacer() -> NSView {
        let v = NSView()
        v.setContentHuggingPriority(.init(1), for: .horizontal)
        return v
    }
}
