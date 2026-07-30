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

    enum Layout {
        /// Padding and spacing within the UI
        static let defaultSpacing: CGFloat = 12

        /// Standard default font size
        static let defaultFontSize: CGFloat = 16

        enum ColorCircle {
            /// Circle diameter = defaultFontSize * sizeMultiplier
            static let sizeMultiplier: CGFloat = 1.2
            static let strokeLineWidth: CGFloat = 3
            /// Font size for selected note number = circle size * selectedNumberFontScale
            static let selectedNumberFontScale: CGFloat = 0.8
        }
    }

    enum Window {
        /// Threshold for detecting window unpin
        static let unpinThreshold: CGFloat = 20
    }

    enum Timing {
        /// Debounce interval used when saving text
        static let debounceSave: Duration = .milliseconds(300)
    }
}
