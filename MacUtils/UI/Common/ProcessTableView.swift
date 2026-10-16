import AppKit

public final class ProcessTableView: NSView {
    public enum SortMode {
        case cpu
        case memory
        case network
    }
    
    private let mode: SortMode
    private let stack = NSStackView()
    
    public init(mode: SortMode) {
        self.mode = mode
        super.init(frame: .zero)
        setup()
    }
    
    public required init?(coder: NSCoder) {
        fatalError()
    }
    
    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.spacing = 6
        stack.alignment = .width
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    public func update(processes: [ProcessItem]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        for proc in processes.prefix(5) {
            let val = mode == .cpu ? proc.formattedCPU : proc.formattedMemory
            let row = makeRow(pid: proc.pid, name: proc.name, iconPath: proc.iconPath, value: val, valueWidth: 55)
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }
    
    public func update(networkProcesses: [NetworkProcessItem]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        if networkProcesses.isEmpty {
            let emptyLabel = NSTextField(labelWithString: "No network activity detected")
            emptyLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            emptyLabel.textColor = NSColor.secondaryLabelColor
            stack.addArrangedSubview(emptyLabel)
            emptyLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            return
        }
        
        for proc in networkProcesses.prefix(5) {
            let val = proc.formattedSpeed
            let row = makeRow(pid: proc.pid, name: proc.name, iconPath: proc.iconPath, value: val, valueWidth: 95)
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }
    
    private func makeRow(pid: Int32, name: String, iconPath: String?, value: String, valueWidth: CGFloat) -> NSView {
        let rowView = NSView()
        rowView.translatesAutoresizingMaskIntoConstraints = false
        let stacked = mode == .network
        rowView.heightAnchor.constraint(equalToConstant: stacked ? 32 : 18).isActive = true
        
        // App Icon
        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        if let app = NSRunningApplication(processIdentifier: pid), let icon = app.icon {
            iconView.image = icon
        } else if let iconPath {
            iconView.image = NSWorkspace.shared.icon(forFile: iconPath)
        } else {
            iconView.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)
        }
        rowView.addSubview(iconView)
        
        // Value Label pinned to the RIGHT edge with fixed width
        let valLabel = NSTextField(labelWithString: value)
        valLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        valLabel.alignment = .right
        valLabel.textColor = NSColor.secondaryLabelColor
        valLabel.translatesAutoresizingMaskIntoConstraints = false
        valLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        valLabel.setContentHuggingPriority(.required, for: .horizontal)
        rowView.addSubview(valLabel)
        
        // App Name Label filling remaining space with truncation ellipsis
        let nameLabel = NSTextField(labelWithString: name)
        nameLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        nameLabel.textColor = NSColor.labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.toolTip = name
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        rowView.addSubview(nameLabel)
        
        if stacked {
            // Name gets the full row width; speeds sit on a second line beneath it
            valLabel.alignment = .left
            valLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
            NSLayoutConstraint.activate([
                iconView.leadingAnchor.constraint(equalTo: rowView.leadingAnchor, constant: 4),
                iconView.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: 20),
                iconView.heightAnchor.constraint(equalToConstant: 20),
                
                nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
                nameLabel.trailingAnchor.constraint(equalTo: rowView.trailingAnchor, constant: -4),
                nameLabel.topAnchor.constraint(equalTo: rowView.topAnchor, constant: 1),
                
                valLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
                valLabel.trailingAnchor.constraint(lessThanOrEqualTo: rowView.trailingAnchor, constant: -4),
                valLabel.bottomAnchor.constraint(equalTo: rowView.bottomAnchor, constant: -1)
            ])
            return rowView
        }
        
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: rowView.leadingAnchor, constant: 4),
            iconView.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            
            valLabel.trailingAnchor.constraint(equalTo: rowView.trailingAnchor, constant: -4),
            valLabel.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
            valLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: valueWidth),
            
            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            nameLabel.trailingAnchor.constraint(equalTo: valLabel.leadingAnchor, constant: -8),
            nameLabel.centerYAnchor.constraint(equalTo: rowView.centerYAnchor)
        ])
        
        return rowView
    }
}
