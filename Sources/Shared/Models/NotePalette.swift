import SwiftUI

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
}
