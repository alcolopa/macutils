import AppKit

public final class MetricRowView: NSView {
    private let dot = NSView()
    private let labelView = NSTextField(labelWithString: "")
    private let valView = NSTextField(labelWithString: "")
    
    public init(label: String, color: NSColor) {
        super.init(frame: .zero)
        setup(label: label, color: color)
    }
    
    public required init?(coder: NSCoder) {
        fatalError()
    }
    
    private func setup(label: String, color: NSColor) {
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 18).isActive = true
        
        dot.wantsLayer = true
        dot.layer?.backgroundColor = color.cgColor
        dot.layer?.cornerRadius = 3.0
        dot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dot)
        
        labelView.stringValue = label
        labelView.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        labelView.textColor = NSColor.secondaryLabelColor
        labelView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(labelView)
        
        valView.stringValue = "0%"
        valView.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        valView.textColor = NSColor.labelColor
        valView.alignment = .right
        valView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(valView)
        
        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: leadingAnchor),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),
            
            labelView.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 6),
            labelView.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            valView.trailingAnchor.constraint(equalTo: trailingAnchor),
            valView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    
    public func setValue(_ text: String, tint: NSColor? = nil) {
        valView.stringValue = text
        valView.textColor = tint ?? NSColor.labelColor
    }
}
