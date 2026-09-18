import AppKit
import CoreGraphics

public final class HistoryGraphView: NSView {
    public static let capacity: Int = 120
    
    // Series 1 (primary, e.g. CPU or Download)
    private var series1Buffer: [Double] = Array(repeating: 0.0, count: capacity)
    // Series 2 (optional, e.g. Upload)
    private var series2Buffer: [Double] = Array(repeating: 0.0, count: capacity)
    private var hasSeries2: Bool = false
    
    private var writeIndex: Int = 0
    private var count: Int = 0
    private let lock = NSLock()
    
    public var series1Color: NSColor = .systemBlue
    public var series2Color: NSColor = .systemOrange
    public var maxDisplayValue: Double = 100.0 // 100 for %, or dynamic for network
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }
    
    public func push(val1: Double, val2: Double? = nil) {
        lock.lock()
        series1Buffer[writeIndex] = val1
        if let val2 = val2 {
            series2Buffer[writeIndex] = val2
            hasSeries2 = true
        } else {
            hasSeries2 = false
        }
        writeIndex = (writeIndex + 1) % Self.capacity
        if count < Self.capacity {
            count += 1
        }
        lock.unlock()
        
        needsDisplay = true
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        let rect = bounds
        guard rect.width > 0 && rect.height > 0 else { return }
        
        lock.lock()
        let total = count
        let s2Enabled = hasSeries2
        var s1Snapshot = [Double](repeating: 0.0, count: Self.capacity)
        var s2Snapshot = [Double](repeating: 0.0, count: Self.capacity)
        let startIndex = (writeIndex - total + Self.capacity) % Self.capacity
        for i in 0..<total {
            let idx = (startIndex + i) % Self.capacity
            s1Snapshot[Self.capacity - total + i] = series1Buffer[idx]
            if s2Enabled {
                s2Snapshot[Self.capacity - total + i] = series2Buffer[idx]
            }
        }
        lock.unlock()
        
        context.saveGState()
        
        // Rounded dark container
        let bgPath = CGPath(roundedRect: rect, cornerWidth: 6.0, cornerHeight: 6.0, transform: nil)
        context.addPath(bgPath)
        context.setFillColor(CGColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 0.6))
        context.fillPath()
        
        // Grid lines at 25%, 50%, 75%
        context.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.08))
        context.setLineWidth(0.8)
        context.setLineDash(phase: 0, lengths: [3, 3])
        for pct in [0.25, 0.50, 0.75] {
            let y = rect.origin.y + CGFloat(pct) * rect.height
            context.move(to: CGPoint(x: rect.origin.x, y: y))
            context.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        context.strokePath()
        context.setLineDash(phase: 0, lengths: [])
        
        // Clip to rounded border
        context.addPath(bgPath)
        context.clip()
        
        // Determine dynamic scale if maxDisplayValue is adaptive (e.g. network)
        var scaleMax = maxDisplayValue
        if maxDisplayValue <= 0 {
            let peak1 = s1Snapshot.max() ?? 1.0
            let peak2 = s2Enabled ? (s2Snapshot.max() ?? 1.0) : 1.0
            scaleMax = max(peak1, peak2, 1024.0) * 1.2
        }
        
        if s2Enabled {
            drawSeries(in: context, rect: rect, values: s2Snapshot, maxVal: scaleMax, color: series2Color)
        }
        drawSeries(in: context, rect: rect, values: s1Snapshot, maxVal: scaleMax, color: series1Color)
        
        context.restoreGState()
    }
    
    private func drawSeries(in context: CGContext, rect: CGRect, values: [Double], maxVal: Double, color: NSColor) {
        let pointCount = values.count
        guard pointCount > 1 else { return }
        
        let stepX = rect.width / CGFloat(pointCount - 1)
        let strokePath = CGMutablePath()
        let fillPath = CGMutablePath()
        
        func computeY(_ val: Double) -> CGFloat {
            let clamped = min(max(val / maxVal, 0.0), 1.0)
            return rect.origin.y + CGFloat(clamped) * rect.height
        }
        
        let firstY = computeY(values[0])
        strokePath.move(to: CGPoint(x: rect.origin.x, y: firstY))
        
        fillPath.move(to: CGPoint(x: rect.origin.x, y: rect.origin.y))
        fillPath.addLine(to: CGPoint(x: rect.origin.x, y: firstY))
        
        for i in 1..<pointCount {
            let x = rect.origin.x + CGFloat(i) * stepX
            let y = computeY(values[i])
            strokePath.addLine(to: CGPoint(x: x, y: y))
            fillPath.addLine(to: CGPoint(x: x, y: y))
        }
        
        let lastX = rect.origin.x + CGFloat(pointCount - 1) * stepX
        fillPath.addLine(to: CGPoint(x: lastX, y: rect.origin.y))
        fillPath.closeSubpath()
        
        // Fill
        context.saveGState()
        context.addPath(fillPath)
        context.setFillColor(color.withAlphaComponent(0.25).cgColor)
        context.fillPath()
        context.restoreGState()
        
        // Stroke
        context.saveGState()
        context.addPath(strokePath)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(1.5)
        context.setLineJoin(.round)
        context.strokePath()
        context.restoreGState()
    }
}
