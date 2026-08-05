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
    static var adaptiveEditorText: PlatformColor {
        #if canImport(UIKit)
            .label
        #else
            .textColor
        #endif
    }
}

extension NSAttributedString {
    /// A copy with the adaptive text color filled in wherever no color is set.
    ///
    /// Text layout falls back to opaque black — not the system text color — for runs with no
    /// `.foregroundColor`, and RTF stores no color for such runs (its color table comes back
    /// empty). Notes saved that way therefore stay black and turn unreadable in dark mode.
    ///
    /// Only missing colors are filled in: runs that carry an explicit color keep it, so
    /// pasted formatting still round-trips. Text the editors themselves colored is stored as
    /// the named system color, which stays adaptive across a save and reload.
    func fillingInAdaptiveTextColor() -> NSAttributedString {
        guard length > 0 else { return self }

        let uncolored = uncoloredRanges()
        guard !uncolored.isEmpty else { return self }

        let filled = NSMutableAttributedString(attributedString: self)
        for range in uncolored {
            filled.addAttribute(.foregroundColor, value: PlatformColor.adaptiveEditorText, range: range)
        }
        return filled
    }

    /// Collected up front rather than filled in place: mutating an attributed string while
    /// enumerating its attributes is not allowed.
    private func uncoloredRanges() -> [NSRange] {
        var ranges: [NSRange] = []
        enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: length)) { color, range, _ in
            if color == nil {
                ranges.append(range)
            }
        }
        return ranges
    }
}
