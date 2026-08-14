import Foundation

/// Which note is showing: validated on the read, so nothing downstream has to defend itself.
///
/// The stored value is plain `UserDefaults` — writable from outside the app, and carried across
/// versions that may not have had seven notes — and nothing sanity-checks it on the way in.
/// Indexing an array with it raw turns a junk value into a crash at launch, in a menubar app
/// with no window and no Dock icon: clicking the icon would simply do nothing, with no visible
/// explanation. Clamping once here is what lets `ContentView` hand every reader an index that
/// is already known good, instead of each of them guarding, repairing or crashing on its own.
///
/// Validation lives on the read, and only there. Both functions below say who their callers are,
/// because "the single point of validation" was read as "the single caller" and is not.
enum NoteSelection {

    /// `index` brought inside `0..<noteCount`.
    ///
    /// Bounded by the array actually being subscripted rather than by `AppConstants.noteCount`:
    /// the caller knows how many notes it has in hand, and the palette stays safe on the
    /// one-colour-per-note invariant `NotePaletteTests` pins.
    ///
    /// **Two readers, bounding two different things.** `ContentView` bounds a stored selection by
    /// `notes.count`; `NotePalette.boldTint` bounds a palette index by `colors.count`. Both are
    /// positions and both want the same arithmetic, but they are not the same invariant — a change
    /// to what clamping *means* has to be made against both.
    ///
    /// `0` is what an empty array yields, which is not a usable index — with nothing to select
    /// there is no answer, and callers must not subscript with it. `ContentView` reads the
    /// selection only where `notes.count` has already checked out.
    static func clamped(_ index: Int, noteCount: Int) -> Int {
        guard noteCount > 0 else { return 0 }
        return min(max(index, 0), noteCount - 1)
    }

    /// Stores `index` where `ContentView`'s `@AppStorage` will pick it up — for callers that have
    /// no binding to write through.
    ///
    /// **Not the only writer, and not meant to be.** `ContentView.selection`'s setter assigns
    /// through the `@AppStorage` projection, which is how the colour circles write, and going
    /// around SwiftUI to reach this function instead would cost the write its transaction — the
    /// selection animation among it. This is the door for `EditorShortcutManager`, which has
    /// keystrokes and no view.
    ///
    /// Deliberately unvalidated either way: validating on the write would be a second point of
    /// validation, and neither writer holds anything but a real note index.
    static func store(_ index: Int, in defaults: UserDefaults) {
        defaults.set(index, forKey: AppConstants.selectedNoteIndexKey)
    }
}
