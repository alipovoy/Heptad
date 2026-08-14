import CoreGraphics
import Foundation

extension Notification.Name {
    /// Posted when `⌘+` or `⌘-` moves the editor font size. The editor coordinators observe it
    /// and repaint every cached note.
    static let editorFontSizeDidChange = Notification.Name("Heptad.editorFontSizeDidChange")
}

/// The size the editor draws every note at.
///
/// One size for the whole app rather than one per run of text. Under RTF storage `⌘+` wrote a
/// `.font` attribute into the selection, which made font size the one piece of formatting with
/// no markdown spelling — and so the one piece that could not survive the swap to a text buffer
/// (#117). A zoom level is what it always really was for a scratchpad.
enum EditorFontSize {
    /// The current size, clamped on read: the value is plain `UserDefaults` and is writable from
    /// outside the app, and a junk one would otherwise reach text layout.
    static func current(_ defaults: UserDefaults = .standard) -> CGFloat {
        guard let stored = defaults.object(forKey: AppConstants.editorFontSizeKey) as? Double
        else { return AppConstants.Layout.defaultFontSize }

        return clamped(CGFloat(stored))
    }

    /// Steps the size by two points and reports the new one, or nil when it was already at the
    /// bound in that direction — in which case nothing is written and nothing is posted, so a
    /// held-down `⌘+` stops repainting once it hits the ceiling.
    @discardableResult
    static func step(
        increase: Bool,
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) -> CGFloat? {
        let size = current(defaults)
        let stepped = clamped(size + (increase ? 2 : -2))
        guard stepped != size else { return nil }

        defaults.set(Double(stepped), forKey: AppConstants.editorFontSizeKey)
        notificationCenter.post(name: .editorFontSizeDidChange, object: nil)
        return stepped
    }

    /// `isFinite` first, because `min`/`max` are comparisons and every comparison against NaN is
    /// false — so a stored NaN fell through both bounds untouched, and it is the one junk value
    /// that also sticks: `step` bails on `stepped != size`, which NaN never satisfies, so ⌘+ and
    /// ⌘- both wrote it back and posted, at a size AppKit silently substitutes 13 pt for. There
    /// was no way back from inside the app. Infinities land on the default for the same reason
    /// rather than on a bound: neither is a size anyone asked for.
    private static func clamped(_ size: CGFloat) -> CGFloat {
        guard size.isFinite else { return AppConstants.Layout.defaultFontSize }

        return min(max(size, AppConstants.Layout.minFontSize), AppConstants.Layout.maxFontSize)
    }
}
