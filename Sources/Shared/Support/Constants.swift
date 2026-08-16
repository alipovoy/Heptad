import CoreGraphics
import Foundation

/// The values more than one file has to agree on.
///
/// That is the whole membership rule, and it is narrower than "every number in the app": a
/// constant with one reader belongs in that file, beside the code it describes. A value here is a
/// promise that two files stay in step.
enum AppConstants {
    /// The app always has exactly this many notes (one per color).
    static let noteCount = 7

    /// UserDefaults key backing the currently selected note. Shared between the
    /// @AppStorage binding in ContentView and the note-switching shortcuts, so the
    /// two never drift apart.
    static let selectedNoteIndexKey = "selectedNoteIndex"

    /// UserDefaults keys backing the global summon hotkey (macOS only). The keycode is a
    /// virtual `kVK_*` value and the modifiers are a Cocoa `NSEvent.ModifierFlags` raw value;
    /// the ⌃⌥Space defaults live in GlobalHotKeyManager, which can name those constants.
    static let globalHotKeyKeyCodeKey = "globalHotKeyKeyCode"
    static let globalHotKeyModifierFlagsKey = "globalHotKeyModifierFlags"

    /// UserDefaults key backing the editor's zoom level, which `⌘+` and `⌘-` step. One size for
    /// every note: see `EditorFontSize`.
    static let editorFontSizeKey = "editorFontSize"

    enum Layout {
        /// Padding and spacing within the UI
        static let defaultSpacing: CGFloat = 12

        /// Standard default font size
        static let defaultFontSize: CGFloat = 16

        /// The inset the window's chrome keeps from its sides — the title bar's buttons and the
        /// statistics bar's text and toggles — so the two line up down the window's edges.
        static let edgeInset: CGFloat = 14

        /// The room above and below a row of chrome: the statistics bar on both platforms, and
        /// iOS's note switcher, which has no title bar to sit in.
        static let rowInset: CGFloat = 8

        /// How much of the selected note's colour the window is washed with.
        ///
        /// Read by the view that paints it and by the test that checks every bold tint clears WCAG
        /// AA against it — with its own copy, that test would keep passing while the app went
        /// unreadable.
        static let noteTintOpacity: Double = 0.1
    }

    enum Window {
        /// The gap between the status item and the top of the panel hanging below it. Read by the
        /// window manager that positions the panel and by the tests that check where it landed.
        static let statusItemGap: CGFloat = 5

        /// The panel's smallest content size, declared by `ContentView` and read back by
        /// `WindowManager` for the size it opens at.
        ///
        /// The view cannot help being the source of truth for the width: `NSHostingView` installs
        /// its root's minimum as the window's `contentMinSize` and grows the window to satisfy it,
        /// so a narrower `contentRect` never survives.
        static let minimumContentSize = CGSize(width: 320, height: 200)

        /// What the panel is built at, before any autosaved frame is restored. Only the height is
        /// its own: the width is the minimum above, because that is what it would be given anyway.
        static let openingContentSize = CGSize(width: minimumContentSize.width, height: 400)
    }
}
