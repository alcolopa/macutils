import AppKit
import CoreGraphics

public final class CPUGraphRenderer: @unchecked Sendable {
    public static let capacity: Int = 120 // 60 seconds at 2Hz
    
    // Fixed-size circular ring buffer
    private var buffer: [Double] = Array(repeating: 0.0, count: capacity)
    private var writeIndex: Int = 0
    private var count: Int = 0
    private let lock = NSLock()
    
    // Framerate throttle tracking (max 30 FPS ~ 0.033s)
    private var lastRenderTime: TimeInterval = 0
    private let minRenderInterval: TimeInterval = 0.033
    
    public init() {}
    
    public func push(value: Double) {
        lock.lock()
        buffer[writeIndex] = min(max(value, 0.0), 100.0)
        writeIndex = (writeIndex + 1) % Self.capacity
        if count < Self.capacity {
            count += 1
        }
        lock.unlock()
    }
    
    /// Populates pre-allocated array with values ordered oldest to newest.
    public func snapshotValues() -> [Double] {
        lock.lock()
        defer { lock.unlock() }
        var result = [Double](repeating: 0.0, count: Self.capacity)
        let total = count
        if total == 0 {
            return result
        }
        let startIndex = (writeIndex - total + Self.capacity) % Self.capacity
        for i in 0..<total {
            let idx = (startIndex + i) % Self.capacity
            result[Self.capacity - total + i] = buffer[idx]
        }
        return result
    }
    
    /// Checks if a frame can be rendered based on 30 FPS throttle.
    public func shouldRender(now: TimeInterval) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if now - lastRenderTime >= minRenderInterval {
            lastRenderTime = now
            return true
        }
        return false
    }
    
    /// Renders the graph into the context.
    public func render(in context: CGContext, rect: CGRect) {
        guard rect.width > 0 && rect.height > 0 else { return }
        
        let values = snapshotValues()
        
        context.saveGState()
        
        // Background: Flat semi-transparent dark plate (#1E1E1E, 0.4 alpha)
        let bgPath = CGPath(roundedRect: rect, cornerWidth: 4.0, cornerHeight: 4.0, transform: nil)
        context.addPath(bgPath)
        context.setFillColor(CGColor(red: 0.118, green: 0.118, blue: 0.118, alpha: 0.4))
        context.fillPath()
        
        // Clip to rounded background for drawing gradient & stroke
        context.addPath(bgPath)
        context.clip()
        
        let pointCount = values.count
        guard pointCount > 1 else {
            context.restoreGState()
            return
        }
        
        let stepX = rect.width / CGFloat(pointCount - 1)
        let strokePath = CGMutablePath()
        let fillPath = CGMutablePath()
        
        // Starting point
        let firstY = rect.origin.y + (CGFloat(values[0]) / 100.0) * rect.height
        strokePath.move(to: CGPoint(x: rect.origin.x, y: firstY))
        
        fillPath.move(to: CGPoint(x: rect.origin.x, y: rect.origin.y))
        fillPath.addLine(to: CGPoint(x: rect.origin.x, y: firstY))
        
        for i in 1..<pointCount {
            let x = rect.origin.x + CGFloat(i) * stepX
            let y = rect.origin.y + (CGFloat(values[i]) / 100.0) * rect.height
            strokePath.addLine(to: CGPoint(x: x, y: y))
            fillPath.addLine(to: CGPoint(x: x, y: y))
        }
        
        let lastX = rect.origin.x + CGFloat(pointCount - 1) * stepX
        fillPath.addLine(to: CGPoint(x: lastX, y: rect.origin.y))
        fillPath.closeSubpath()
        
        // Gradient Fill: System Blue (#007AFF) at 30% alpha fading to 0% alpha at base
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let colors = [
            CGColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 0.30),
            CGColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 0.0)
        ] as CFArray
        let locations: [CGFloat] = [1.0, 0.0]
        
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
            context.saveGState()
            context.addPath(fillPath)
            context.clip()
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: rect.midX, y: rect.maxY),
                end: CGPoint(x: rect.midX, y: rect.origin.y),
                options: []
            )
            context.restoreGState()
        }
        
        // Path stroke: #007AFF (System Blue), line width: 1.5pt
        context.saveGState()
        context.addPath(strokePath)
        context.setStrokeColor(CGColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0))
        context.setLineWidth(1.5)
        context.setLineJoin(.round)
        context.strokePath()
        context.restoreGState()
        
        context.restoreGState()
    }
}
