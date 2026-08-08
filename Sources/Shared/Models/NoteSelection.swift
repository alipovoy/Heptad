import Foundation

/// Which note is showing: validated on the read, so nothing downstream has to defend itself.
///
/// The stored value is plain `UserDefaults` — writable from outside the app, and carried across
/// versions that may not have had seven notes — and nothing sanity-checks it on the way in.
/// Indexing an array with it raw turns a junk value into a crash at launch, in a menubar app
/// with no window and no Dock icon: clicking the icon would simply do nothing, with no visible
/// explanation. Clamping once here is what lets `ContentView` hand every reader an index that
/// is already known good, instead of each of them guarding, repairing or crashing on its own.
enum NoteSelection {

    /// `index` brought inside `0..<noteCount`.
    ///
    /// Bounded by the array actually being subscripted rather than by `AppConstants.noteCount`:
    /// the caller knows how many notes it has in hand, and the palette stays safe on the
    /// one-colour-per-note invariant `NotePaletteTests` pins.
    ///
    /// `0` is what an empty array yields, which is not a usable index — with nothing to select
    /// there is no answer, and callers must not subscript with it. `ContentView` reads the
    /// selection only where `notes.count` has already checked out.
    static func clamped(_ index: Int, noteCount: Int) -> Int {
        guard noteCount > 0 else { return 0 }
        return min(max(index, 0), noteCount - 1)
    }

    /// Stores `index` where `ContentView`'s `@AppStorage` will pick it up.
    ///
    /// Deliberately unvalidated: the read is the single point of validation, and a writer that
    /// repaired the stored value would be the second. Callers hold a real note index.
    static func store(_ index: Int, in defaults: UserDefaults) {
        defaults.set(index, forKey: AppConstants.selectedNoteIndexKey)
    }
}
