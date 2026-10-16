import AppKit

/// Warning / danger colouring for popovers: normal values keep their usual colour.
public enum Severity {
    case normal, warning, danger
    
    /// `value >= danger` is danger, `value >= warning` is warning.
    public static func level(_ value: Double, warning: Double, danger: Double) -> Severity {
        value >= danger ? .danger : (value >= warning ? .warning : .normal)
    }
    
    public func color(normal: NSColor) -> NSColor {
        switch self {
        case .normal:  return normal
        case .warning: return .systemOrange
        case .danger:  return .systemRed
        }
    }
    
    /// Text tint: nil (default label colour) when normal.
    public var textTint: NSColor? {
        switch self {
        case .normal:  return nil
        case .warning: return .systemOrange
        case .danger:  return .systemRed
        }
    }
}
