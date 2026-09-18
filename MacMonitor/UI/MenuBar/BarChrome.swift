import AppKit

/// Shared menu bar decoration (icon, short label, padding) drawn around each widget's own content.
@MainActor
public enum BarChrome {
    private static let gap: CGFloat = 3
    
    static func shortLabel(for metric: MetricType) -> String {
        switch metric {
        case .cpu:          return "CPU"
        case .memory:       return "MEM"
        case .disk:         return "SSD"
        case .network:      return "NET"
        case .battery:      return "BAT"
        case .temperatures: return "TMP"
        case .displays:     return "DSP"
        case .weather:      return "WX"
        }
    }
    
    private static func labelFont() -> NSFont {
        NSFont.systemFont(ofSize: 7.5, weight: .bold)
    }
    
    private static func labelWidth(_ metric: MetricType) -> CGFloat {
        ceil((shortLabel(for: metric) as NSString).size(withAttributes: [.font: labelFont()]).width)
    }
    
    /// Total width added around the widget's own content.
    public static func extraWidth(for metric: MetricType) -> CGFloat {
        let o = AppPreferences.shared.barOptions(for: metric)
        var w = CGFloat(o.padding) * 2
        if o.showIcon { w += o.iconSize.points + gap }
        if o.showLabel { w += labelWidth(metric) + gap }
        return w
    }
    
    /// Draws the icon/label and returns the rect (origin 0,0, translated context) the widget should draw into.
    public static func begin(metric: MetricType, in view: NSView) -> CGRect {
        let bounds = view.bounds
        let o = AppPreferences.shared.barOptions(for: metric)
        let pad = CGFloat(o.padding)
        let isDark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let base: NSColor = isDark ? .white : .black
        let iconColor = o.iconTint == .theme ? AppPreferences.shared.colorTheme.primaryColor : base
        
        let iconW = o.showIcon ? o.iconSize.points : 0
        let labelW = o.showLabel ? labelWidth(metric) : 0
        var chromeW: CGFloat = 0
        if o.showIcon { chromeW += iconW + gap }
        if o.showLabel { chromeW += labelW + gap }
        
        let contentW = max(bounds.width - chromeW - pad * 2, 1)
        let contentX: CGFloat
        var cursor: CGFloat
        if o.iconPosition == .leading {
            cursor = pad
            contentX = pad + chromeW
        } else {
            contentX = pad
            cursor = pad + contentW + gap
        }
        
        if o.showIcon,
           let img = NSImage(systemSymbolName: metric.iconSymbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: iconW, weight: .medium)
                .applying(NSImage.SymbolConfiguration(paletteColors: [iconColor]))) {
            let ratio = img.size.height > 0 ? img.size.width / img.size.height : 1
            let h = iconW
            let w = min(h * ratio, iconW)
            img.draw(in: CGRect(x: cursor + (iconW - w) / 2, y: (bounds.height - h) / 2, width: w, height: h))
            cursor += iconW + gap
        }
        if o.showLabel {
            let attrs: [NSAttributedString.Key: Any] = [.font: labelFont(), .foregroundColor: base.withAlphaComponent(0.7)]
            let str = NSAttributedString(string: shortLabel(for: metric), attributes: attrs)
            str.draw(at: CGPoint(x: cursor, y: (bounds.height - str.size().height) / 2))
        }
        
        NSGraphicsContext.current?.cgContext.translateBy(x: contentX, y: 0)
        return CGRect(x: 0, y: 0, width: contentW, height: bounds.height)
    }
}
