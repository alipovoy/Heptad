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

    /// UserDefaults key backing the pinned window state (macOS only). True means the regular,
    /// stays-put window the pin toggle and ⌘P produce; false means the menubar panel that
    /// dismisses itself on a click outside. WindowManager is the only writer; the title-bar
    /// toggle reads it through @AppStorage to render the current state.
    static let windowPinnedKey = "windowPinned"

    enum Layout {
        /// Padding and spacing within the UI
        static let defaultSpacing: CGFloat = 12

        /// Standard default font size
        static let defaultFontSize: CGFloat = 16

        /// Font size of the statistics line beneath the editor.
        static let statisticsFontSize: CGFloat = 11

        /// Icon sizes in the macOS window chrome: the title-bar close button, and the pin
        /// toggle, which is sized against the statistics text it sits beside rather than
        /// against the title bar. Deliberately fixed rather than Dynamic Type — the panel is
        /// a fixed-size menubar popover and accessibility sizes would break its layout.
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
    }

    enum Timing {
        /// Debounce interval used when saving text
        static let debounceSave: Duration = .milliseconds(300)
    }
}
