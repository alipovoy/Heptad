import SwiftUI

#if canImport(UIKit)
    import UIKit
#else
    import AppKit
#endif

/// The seven note colors, in note order: note *n* is always `colors[n]`.
///
/// App-wide data rather than view state, which is why it does not live on `ContentView` —
/// the colour a note is drawn in is as much a property of the note as its text. Not in
/// `AppConstants` either: that file imports only Foundation and CoreGraphics, and `Color`
/// would drag SwiftUI into every file that reads a constant.
///
/// `colors.count == AppConstants.noteCount` is an invariant — one colour per note, and the
/// palette is indexed by note index throughout. `NotePaletteTests` pins it; the readers that
/// index it still clamp, because the stored selection they index with comes from UserDefaults.
enum NotePalette {
    static let colors: [Color] = [.red, .orange, .yellow, .green, .cyan, .blue, .purple]

    /// The colour bold text is drawn in on note `index`, in formatted mode.
    ///
    /// Clamped here because this is the only door to `boldTints`: the index arrives from a stored
    /// selection, and a scratchpad should not trap over a colour.
    static func boldTint(forNoteIndex index: Int) -> PlatformColor {
        boldTints[NoteSelection.clamped(index, noteCount: colors.count)]
    }

    /// One dynamic colour per note, derived once. The derivation resolves an appearance and
    /// converts a colour space, and this is read once per bold run on every repaint.
    private static let boldTints: [PlatformColor] = colors.map(tint(of:))

    #if !canImport(UIKit)
        /// The two appearances the tint below chooses between. Hoisted because AppKit runs that
        /// closure on every resolve, and the answer never changes.
        private static let appearances: [NSAppearance.Name] = [.aqua, .darkAqua]
    #endif

    /// A palette entry's hue, at a fixed saturation and brightness per appearance.
    ///
    /// Fixing those rather than taking them from the entry is the point: `.yellow` and `.blue`
    /// arrive at wildly different brightnesses and would read as different weights of text rather
    /// than different colours of it. Light mode goes darker than the paper; dark mode is already
    /// at full brightness, so its contrast comes from draining colour toward white instead. Every
    /// hue clears AA for body text against its own note at these values.
    private static func tint(of color: Color) -> PlatformColor {
        let hue = hue(of: color)
        let light = PlatformColor(hue: hue, saturation: 1.0, brightness: 0.5, alpha: 1)
        let dark = PlatformColor(hue: hue, saturation: 0.35, brightness: 1.0, alpha: 1)

        #if canImport(UIKit)
            return PlatformColor { $0.userInterfaceStyle == .dark ? dark : light }
        #else
            return PlatformColor(name: nil) { appearance in
                appearance.bestMatch(from: Self.appearances) == .darkAqua ? dark : light
            }
        #endif
    }

    /// Read in light appearance deliberately: the palette entries are themselves dynamic, and
    /// resolving against whatever is current would make the tint depend on the mode twice.
    ///
    /// The conversion does not fail for the system colours the palette holds. If it ever did,
    /// every note would tint red — wrong, but not worth taking a scratchpad down over.
    private static func hue(of color: Color) -> CGFloat {
        guard let rgb = PlatformColor(color).resolved(dark: false) else { return 0 }

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        return hue
    }
}
