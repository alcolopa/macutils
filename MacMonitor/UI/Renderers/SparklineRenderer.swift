import AppKit
import CoreGraphics

public enum SparklineRenderer {
    /// Renders a miniature 5-bar sparkline into the given CGContext.
    /// - Parameters:
    ///   - context: The CGContext to render into.
    ///   - rect: Bounding box for the sparkline.
    ///   - values: Up to 5 load values between 0.0 and 100.0.
    public static func render(in context: CGContext, rect: CGRect, values: [Double]) {
        guard rect.width > 0 && rect.height > 0 else { return }
        
        let barCount = 5
        let spacing: CGFloat = 1.0
        let totalSpacing = spacing * CGFloat(barCount - 1)
        let barWidth = max((rect.width - totalSpacing) / CGFloat(barCount), 1.0)
        
        // Pad values to barCount if needed, taking the last 5
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
            let barHeight = max(rect.height * fraction, 1.0)
            let x = rect.origin.x + CGFloat(i) * (barWidth + spacing)
            let y = rect.origin.y // AppKit default flipped context or standard
            
            let barRect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
            
            // Color based on load intensity
            let barColor: CGColor
            if val > 80.0 {
                barColor = CGColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 0.9) // Red
            } else if val > 50.0 {
                barColor = CGColor(red: 1.0, green: 0.58, blue: 0.0, alpha: 0.9)  // Orange
            } else {
                barColor = CGColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 0.85) // System Blue
            }
            
            context.setFillColor(barColor)
            let roundedPath = CGPath(roundedRect: barRect, cornerWidth: 0.5, cornerHeight: 0.5, transform: nil)
            context.addPath(roundedPath)
            context.fillPath()
        }
        
        context.restoreGState()
    }
}
