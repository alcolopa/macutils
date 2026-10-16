import AppKit

/// An NSView whose coordinate system is flipped (y = 0 is at the top).
/// When used as the documentView in an NSScrollView, the scroll view defaults
/// to showing the top of the content instead of the bottom.
open class FlippedView: NSView {
    open override var isFlipped: Bool {
        return true
    }
}

/// An NSStackView whose coordinate system is flipped (y = 0 is at the top).
/// Ensures proper top-to-bottom layout alignment and top-anchored scrolling in NSScrollView.
open class FlippedStackView: NSStackView {
    open override var isFlipped: Bool {
        return true
    }
}
