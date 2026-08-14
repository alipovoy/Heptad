import CoreGraphics
import Foundation

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

    /// The most markup ⌘V will decode before falling back to pasting the clipboard's characters.
    /// See `NSPasteboard.markdownForPaste`, which is the only reader and explains the number.
    static let richPasteByteLimit = 1 << 20

    enum Layout {
        /// Padding and spacing within the UI
        static let defaultSpacing: CGFloat = 12

        /// Standard default font size
        static let defaultFontSize: CGFloat = 16

        /// Bounds ⌘+ and ⌘- step between. Both ends matter: without the ceiling a held ⌘+
        /// grows the font without limit, and without the floor ⌘- walks it down through zero.
        static let minFontSize: CGFloat = 8
        static let maxFontSize: CGFloat = 72

        /// Font size of the statistics line beneath the editor.
        static let statisticsFontSize: CGFloat = 11

        /// The title-bar close button, and the toggles in the statistics bar — the pin, and the
        /// plain-text switch beside it, both sized against that text rather than the title bar.
        ///
        /// These are the *base* sizes, not the drawn ones. On macOS they are drawn as they stand:
        /// the panel is a fixed menubar popover and accessibility text sizes would break the
        /// layout built around them. iOS is a full-screen window with a text size the user sets,
        /// so its readers scale these with `@ScaledMetric` — the licence above was always about a
        /// window iOS does not have.
        static let titleBarIconSize: CGFloat = 18
        static let pinToggleIconSize: CGFloat = 13

        enum ColorCircle {
            /// Circle diameter = defaultFontSize * sizeMultiplier
            static let sizeMultiplier: CGFloat = 1.2
            static let strokeLineWidth: CGFloat = 3
            /// Font size for selected note number = circle size * selectedNumberFontScale
            static let selectedNumberFontScale: CGFloat = 0.8
        }
    }

    enum Window {
        /// Distance the panel must be dragged away from its menubar anchor to become pinned
        static let dragToPinThreshold: CGFloat = 20

        /// The panel's smallest content size, declared by `ContentView` and read back by
        /// `WindowManager` for the size it opens at.
        ///
        /// The view is the source of truth for the width because it cannot help being:
        /// `NSHostingView` installs its root's minimum as the window's `contentMinSize` and grows
        /// the window to satisfy it, so a narrower `contentRect` never survived first contact —
        /// the panel opened at this width whatever the window manager asked for.
        static let minimumContentSize = CGSize(width: 320, height: 200)

        /// What the panel is built at, before any autosaved frame is restored. Only the height is
        /// its own: the width is the minimum above, because that is what it would be given anyway.
        static let openingContentSize = CGSize(width: minimumContentSize.width, height: 400)
    }

    enum Timing {
        /// Debounce interval used when saving text
        static let debounceSave: Duration = .milliseconds(300)

        /// The longest a burst of typing may go unwritten, however continuous it is.
        ///
        /// The debounce alone means "300 ms after you stop", not "at most 300 ms": anything above
        /// roughly 40 wpm keeps rearming the timer, and a paragraph typed without a pause lives
        /// only in the text view. This bounds what a crash can take.
        static let maxSaveDelay: Duration = .seconds(2)

        /// How often `RelativeTimeTicker` re-reads the clock while the window is on screen.
        /// Coarse on purpose — the edit-time label is a staleness cue, not a stopwatch.
        static let relativeTimeRefresh: Duration = .seconds(30)
    }
}
