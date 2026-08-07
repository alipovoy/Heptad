import Foundation

#if canImport(UIKit)
    import UIKit

    typealias PlatformColor = UIColor
#else
    import AppKit

    typealias PlatformColor = NSColor
#endif

extension PlatformColor {
    /// The system's body-text color: black in light appearance, white in dark.
    ///
    /// Applied to the whole note on every repaint by `MarkdownStyling`, which is what keeps it
    /// adaptive. Under RTF storage this had to be filled in on load instead — text layout falls
    /// back to opaque black for runs with no `.foregroundColor`, and RTF stores no colour for
    /// such runs, so notes went unreadable in dark mode. Nothing is stored now, so there is
    /// nothing to fill in.
    static var adaptiveEditorText: PlatformColor {
        #if canImport(UIKit)
            .label
        #else
            .textColor
        #endif
    }
}
