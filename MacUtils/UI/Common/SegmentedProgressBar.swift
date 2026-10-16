import AppKit

public struct BarSegment {
    public let ratio: Double      // 0.0 to 1.0
    public let color: NSColor
    
    public init(ratio: Double, color: NSColor) {
        self.ratio = max(0.0, ratio)
        self.color = color
    }
}

public final class SegmentedProgressBar: NSView {
    private var segments: [BarSegment] = []
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 4.0
        layer?.masksToBounds = true
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.cornerRadius = 4.0
        layer?.masksToBounds = true
    }
    
    public func setSegments(_ segments: [BarSegment]) {
        self.segments = segments
        needsDisplay = true
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        let rect = bounds
        // Background track
        context.setFillColor(NSColor.separatorColor.withAlphaComponent(0.25).cgColor)
        context.fill(rect)
        
        var currentX: CGFloat = 0.0
        let totalWidth = rect.width
        
        for segment in segments {
            let segWidth = totalWidth * CGFloat(segment.ratio)
            if segWidth > 0.5 {
                let segRect = CGRect(x: currentX, y: 0, width: segWidth, height: rect.height)
                context.setFillColor(segment.color.cgColor)
                context.fill(segRect)
                currentX += segWidth
            }
        }
    }
}
