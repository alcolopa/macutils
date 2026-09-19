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
    
    /// Gap between neighbouring parts.
    static let partGap: CGFloat = gap
    
    /// Total width of the elements themselves (excluding icon, label, gaps and padding).
    public static func elementsWidth(for metric: MetricType, widthFor: (MetricDisplayStyle) -> CGFloat) -> CGFloat {
        AppPreferences.shared.barOptions(for: metric).styles.reduce(0) { $0 + widthFor($1) }
    }
    
    /// Width added around the elements: padding, icon, label and the gaps between all parts.
    public static func extraWidth(for metric: MetricType) -> CGFloat {
        let o = AppPreferences.shared.barOptions(for: metric)
        var w = CGFloat(o.padding) * 2
        if o.showIcon { w += o.iconSize.points }
        if o.showLabel { w += labelWidth(metric) }
        w += CGFloat(max(o.order.count - 1, 0)) * gap
        return w
    }
    
    /// Lays out the widget's parts left to right. The icon and label are drawn here; each element is drawn
    /// by `element` into a rect at origin (0,0) of width `widthFor(style)` (the context is translated for it).
    public static func draw(
        metric: MetricType,
        in view: NSView,
        widthFor: (MetricDisplayStyle) -> CGFloat,
        element: (MetricDisplayStyle, CGRect) -> Void
    ) {
        let bounds = view.bounds
        let o = AppPreferences.shared.barOptions(for: metric)
        let isDark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let base: NSColor = isDark ? .white : .black
        let iconColor = base
        let iconW = o.iconSize.points
        var cursor = CGFloat(o.padding)
        
        for part in o.order {
            switch part {
            case .icon:
                if let img = NSImage(systemSymbolName: metric.iconSymbolName, accessibilityDescription: nil)?
                    .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: iconW, weight: .medium)
                        .applying(NSImage.SymbolConfiguration(paletteColors: [iconColor]))) {
                    let ratio = img.size.height > 0 ? img.size.width / img.size.height : 1
                    let w = min(iconW * ratio, iconW)
                    img.draw(in: CGRect(x: cursor + (iconW - w) / 2, y: (bounds.height - iconW) / 2, width: w, height: iconW))
                }
                cursor += iconW + gap
            case .label:
                let attrs: [NSAttributedString.Key: Any] = [.font: labelFont(), .foregroundColor: base.withAlphaComponent(0.7)]
                let str = NSAttributedString(string: shortLabel(for: metric), attributes: attrs)
                str.draw(at: CGPoint(x: cursor, y: (bounds.height - str.size().height) / 2))
                cursor += labelWidth(metric) + gap
            case .element(let style):
                let w = widthFor(style)
                if let ctx = NSGraphicsContext.current?.cgContext {
                    ctx.saveGState()
                    ctx.translateBy(x: cursor, y: 0)
                    element(style, CGRect(x: 0, y: 0, width: w, height: bounds.height))
                    ctx.restoreGState()
                }
                cursor += w + gap
            }
        }
    }
}
