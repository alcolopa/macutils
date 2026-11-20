import AppKit

@MainActor
public final class ScreenColorPicker {
    public static let shared = ScreenColorPicker()
    
    private init() {}
    
    public nonisolated static func formatColor(r: CGFloat, g: CGFloat, b: CGFloat, as format: ColorPickerFormat) -> String {
        let rc = min(max(r, 0.0), 1.0)
        let gc = min(max(g, 0.0), 1.0)
        let bc = min(max(b, 0.0), 1.0)
        
        let ri = Int((rc * 255.0).rounded())
        let gi = Int((gc * 255.0).rounded())
        let bi = Int((bc * 255.0).rounded())
        
        switch format {
        case .hex:
            return String(format: "#%02X%02X%02X", ri, gi, bi)
        case .rgb:
            return "rgb(\(ri), \(gi), \(bi))"
        case .hsl:
            let maxV = max(rc, max(gc, bc))
            let minV = min(rc, min(gc, bc))
            let delta = maxV - minV
            let l = (maxV + minV) / 2.0
            let s: CGFloat
            if delta == 0 {
                s = 0
            } else {
                s = delta / (1.0 - abs(2.0 * l - 1.0))
            }
            var h: CGFloat = 0
            if delta > 0 {
                if maxV == rc {
                    h = ((gc - bc) / delta).truncatingRemainder(dividingBy: 6.0)
                } else if maxV == gc {
                    h = ((bc - rc) / delta) + 2.0
                } else {
                    h = ((rc - gc) / delta) + 4.0
                }
                h *= 60.0
                if h < 0 { h += 360.0 }
            }
            return "hsl(\(Int(h.rounded())), \(Int((s * 100.0).rounded()))%, \(Int((l * 100.0).rounded()))%)"
        }
    }
    
    public func pickColor(format: ColorPickerFormat? = nil, completion: (@Sendable (String?) -> Void)? = nil) {
        let chosenFormat = format ?? AppPreferences.shared.colorPickerFormat
        NSColorSampler().show { selectedColor in
            guard let color = selectedColor else {
                completion?(nil)
                return
            }
            
            let srgb = color.usingColorSpace(.sRGB) ?? color
            let formatted = Self.formatColor(
                r: srgb.redComponent,
                g: srgb.greenComponent,
                b: srgb.blueComponent,
                as: chosenFormat
            )
            
            Task { @MainActor in
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(formatted, forType: .string)
                ClipboardStore.shared.add(formatted)
                NSSound.beep()
                completion?(formatted)
            }
        }
    }
}
