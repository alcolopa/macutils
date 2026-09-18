import AppKit
import CoreGraphics

public enum StatusItemRenderer {
    
    /// Renders a multi-colored donut/circular ring (e.g. for Memory: App, Wired, Compressed, Free).
    /// Segments are (fraction 0.0...1.0, color).
    public static func drawMulticolorCircle(
        in context: CGContext,
        rect: CGRect,
        segments: [(fraction: Double, color: NSColor)],
        trackColor: NSColor = NSColor.separatorColor.withAlphaComponent(0.25),
        lineWidth: CGFloat = 2.5
    ) {
        guard rect.width > 0 && rect.height > 0 else { return }
        
        let diameter = min(rect.width, rect.height) - lineWidth
        guard diameter > 0 else { return }
        
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = diameter / 2.0
        
        context.saveGState()
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        
        // Draw track ring
        context.setStrokeColor(trackColor.cgColor)
        context.addArc(center: center, radius: radius, startAngle: 0, endAngle: CGFloat.pi * 2, clockwise: false)
        context.strokePath()
        
        // Segments start at top (12 o'clock, which is π/2 in standard CG coordinates)
        var startAngle: CGFloat = CGFloat.pi / 2.0
        
        for segment in segments {
            let angleDelta = CGFloat(min(max(segment.fraction, 0.0), 1.0) * 2.0 * Double.pi)
            if angleDelta <= 0.001 { continue }
            
            let endAngle = startAngle - angleDelta
            
            context.setStrokeColor(segment.color.cgColor)
            context.beginPath()
            context.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
            context.strokePath()
            
            startAngle = endAngle
        }
        
        context.restoreGState()
    }
    
    /// Renders a single-color circular gauge ring from 0 to 100%.
    public static func drawCircularGauge(
        in context: CGContext,
        rect: CGRect,
        percentage: Double,
        fillColor: NSColor,
        trackColor: NSColor = NSColor.separatorColor.withAlphaComponent(0.25),
        lineWidth: CGFloat = 2.5
    ) {
        guard rect.width > 0 && rect.height > 0 else { return }
        
        let diameter = min(rect.width, rect.height) - lineWidth
        guard diameter > 0 else { return }
        
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = diameter / 2.0
        
        context.saveGState()
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        
        // Track
        context.setStrokeColor(trackColor.cgColor)
        context.addArc(center: center, radius: radius, startAngle: 0, endAngle: CGFloat.pi * 2, clockwise: false)
        context.strokePath()
        
        // Progress arc
        let fraction = min(max(percentage / 100.0, 0.0), 1.0)
        if fraction > 0.01 {
            let startAngle: CGFloat = CGFloat.pi / 2.0
            let endAngle = startAngle - CGFloat(fraction * 2.0 * Double.pi)
            
            context.setStrokeColor(fillColor.cgColor)
            context.beginPath()
            context.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
            context.strokePath()
        }
        
        context.restoreGState()
    }
    
    /// Renders standalone mini vertical activity bars (e.g. CPU or load spark-bars).
    public static func drawBarsOnly(
        in context: CGContext,
        rect: CGRect,
        values: [Double],
        barCount: Int = 4,
        primaryColor: NSColor = .systemBlue
    ) {
        guard rect.width > 0 && rect.height > 0 else { return }
        
        let spacing: CGFloat = 1.5
        let totalSpacing = spacing * CGFloat(barCount - 1)
        let barWidth = max((rect.width - totalSpacing) / CGFloat(barCount), 1.5)
        
        var paddedValues = Array(repeating: 0.0, count: barCount)
        let slice = values.suffix(barCount)
        let offset = barCount - slice.count
        for (i, val) in slice.enumerated() {
            paddedValues[offset + i] = min(max(val, 0.0), 100.0)
        }
        
        context.saveGState()
        
        for i in 0..<barCount {
            let val = paddedValues[i]
            let fraction = CGFloat(val / 100.0)
            let barHeight = max(rect.height * fraction, 1.5)
            let x = rect.origin.x + CGFloat(i) * (barWidth + spacing)
            let y = rect.origin.y + (rect.height - barHeight) / 2.0
            
            let barRect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
            
            let color: CGColor
            if val > 80.0 {
                color = CGColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 0.95)
            } else if val > 50.0 {
                color = CGColor(red: 1.0, green: 0.58, blue: 0.0, alpha: 0.95)
            } else {
                color = primaryColor.cgColor
            }
            
            context.setFillColor(color)
            let path = CGPath(roundedRect: barRect, cornerWidth: 1.0, cornerHeight: 1.0, transform: nil)
            context.addPath(path)
            context.fillPath()
        }
        
        context.restoreGState()
    }
    
    /// Renders a horizontal capsule bar with track and fill.
    public static func drawHorizontalBar(
        in context: CGContext,
        rect: CGRect,
        percentage: Double,
        fillColor: NSColor,
        trackColor: NSColor = NSColor.separatorColor.withAlphaComponent(0.3)
    ) {
        guard rect.width > 0 && rect.height > 0 else { return }
        
        context.saveGState()
        
        // Track
        context.setFillColor(trackColor.cgColor)
        let trackPath = CGPath(roundedRect: rect, cornerWidth: rect.height / 2.0, cornerHeight: rect.height / 2.0, transform: nil)
        context.addPath(trackPath)
        context.fillPath()
        
        // Fill
        let fraction = CGFloat(min(max(percentage / 100.0, 0.0), 1.0))
        let fillWidth = max(rect.width * fraction, 1.5)
        let fillRect = CGRect(x: rect.origin.x, y: rect.origin.y, width: fillWidth, height: rect.height)
        
        context.setFillColor(fillColor.cgColor)
        let fillPath = CGPath(roundedRect: fillRect, cornerWidth: rect.height / 2.0, cornerHeight: rect.height / 2.0, transform: nil)
        context.addPath(fillPath)
        context.fillPath()
        
        context.restoreGState()
    }
}
