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
    /// What `⌘+` and `⌘-` step between. Both ends matter: without the ceiling a held `⌘+` grows the
    /// font without limit, and without the floor `⌘-` walks it down through zero.
    ///
    /// Here rather than in `AppConstants` because `clamped` below is the only thing that reads
    /// them, and its comment is already the explanation they need.
    static let minimumSize: CGFloat = 8
    static let maximumSize: CGFloat = 72

    /// The current size, clamped on read: the value is plain `UserDefaults` and is writable from
    /// outside the app, and a junk one would otherwise reach text layout.
    ///
    /// `defaults` is required here and on `step`. Every caller already passes one, and a
    /// `.standard` default on a store this small only exists to be the wrong thing to reach for
    /// from a test — which is how a suite ends up asserting against the user's own preferences.
    static func current(_ defaults: UserDefaults) -> CGFloat {
        guard let stored = defaults.object(forKey: AppConstants.editorFontSizeKey) as? Double
        else { return AppConstants.Layout.defaultFontSize }

        return clamped(CGFloat(stored))
    }

    /// Steps the size by two points, or does nothing at all when it is already at the bound in
    /// that direction — nothing written and nothing posted, so a held-down `⌘+` stops repainting
    /// once it hits the ceiling.
    ///
    /// Reports nothing: the new size reaches the editors through the notification, which is the
    /// point of having one. It used to hand back a `@discardableResult CGFloat?` that its one
    /// caller discarded and no test read.
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

    /// `isFinite` first, because `min`/`max` are comparisons and every comparison against NaN is
    /// false — so a stored NaN fell through both bounds untouched, and it is the one junk value
    /// that also sticks: `step` bails on `stepped != size`, which NaN never satisfies, so ⌘+ and
    /// ⌘- both wrote it back and posted, at a size AppKit silently substitutes 13 pt for. There
    /// was no way back from inside the app. Infinities land on the default for the same reason
    /// rather than on a bound: neither is a size anyone asked for.
    private static func clamped(_ size: CGFloat) -> CGFloat {
        guard size.isFinite else { return AppConstants.Layout.defaultFontSize }

        return min(max(size, minimumSize), maximumSize)
    }
}
