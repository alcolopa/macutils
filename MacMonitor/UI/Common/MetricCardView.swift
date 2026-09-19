import AppKit

/// A modern macOS styled container card with subtle dark/light material styling, border, and rounded corners.
public final class MetricCardView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let badgeLabel = NSTextField(labelWithString: "")
    private let contentStack = NSStackView()
    
    public init(title: String, badge: String? = nil, contentInsets: NSEdgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 12, right: 12)) {
        super.init(frame: .zero)
        setupView(title: title, badge: badge, contentInsets: contentInsets)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupView(title: String, badge: String?, contentInsets: NSEdgeInsets) {
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.4).cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.25).cgColor
        layer?.borderWidth = 1.0
        layer?.cornerRadius = 8.0
        translatesAutoresizingMaskIntoConstraints = false
        
        // Header
        titleLabel.stringValue = title.uppercased()
        titleLabel.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        titleLabel.textColor = NSColor.secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        
        badgeLabel.stringValue = badge ?? ""
        badgeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold)
        badgeLabel.textColor = NSColor.labelColor
        badgeLabel.alignment = .right
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badgeLabel)
        
        contentStack.orientation = .vertical
        contentStack.spacing = 8
        contentStack.alignment = .width
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            
            badgeLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            badgeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            
            contentStack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: contentInsets.top),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: contentInsets.left),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -contentInsets.right),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -contentInsets.bottom)
        ])
    }
    
    public func setContentSpacing(_ spacing: CGFloat) {
        contentStack.spacing = spacing
    }
    
    public func setBadge(_ text: String, tint: NSColor? = nil) {
        badgeLabel.stringValue = text
        badgeLabel.textColor = tint ?? NSColor.labelColor
    }
    
    public func addContentSubview(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }
}
