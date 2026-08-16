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
    /// What `⌘+` and `⌘-` step between: without the ceiling a held `⌘+` grows the font without
    /// limit, and without the floor `⌘-` walks it down through zero.
    static let minimumSize: CGFloat = 8
    static let maximumSize: CGFloat = 72

    /// The current size, clamped on read: the value is plain `UserDefaults` and is writable from
    /// outside the app, and a junk one would otherwise reach text layout.
    ///
    /// `defaults` is required here and on `step`: a `.standard` default is the wrong thing for a
    /// test to reach for, and a suite that does asserts against the user's own preferences.
    static func current(_ defaults: UserDefaults) -> CGFloat {
        guard let stored = defaults.object(forKey: AppConstants.editorFontSizeKey) as? Double
        else { return AppConstants.Layout.defaultFontSize }

        return clamped(CGFloat(stored))
    }

    /// Steps the size by two points, or does nothing at all when it is already at the bound in
    /// that direction — nothing written and nothing posted, so a held-down `⌘+` stops repainting
    /// once it hits the ceiling.
    ///
    /// Reports nothing: the new size reaches the editors through the notification.
    static func step(
        increase: Bool,
        defaults: UserDefaults,
        notificationCenter: NotificationCenter
    ) {
        let size = current(defaults)
        let stepped = clamped(size + (increase ? 2 : -2))
        guard stepped != size else { return }

        defaults.set(Double(stepped), forKey: AppConstants.editorFontSizeKey)
        notificationCenter.post(name: .editorFontSizeDidChange, object: nil)
    }

    /// `isFinite` first, because every comparison against NaN is false, so a stored NaN falls
    /// through `min`/`max` untouched — and it sticks, since `step` bails on `stepped != size`,
    /// which NaN never satisfies. Infinities land on the default rather than on a bound: neither
    /// is a size anyone asked for.
    private static func clamped(_ size: CGFloat) -> CGFloat {
        guard size.isFinite else { return AppConstants.Layout.defaultFontSize }

        return min(max(size, minimumSize), maximumSize)
    }
}
