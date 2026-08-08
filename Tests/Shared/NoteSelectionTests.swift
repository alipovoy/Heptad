import Foundation
import Testing

@testable import Heptad

/// The clamp that stands between a `UserDefaults` value anyone can write and the arrays every
/// view indexes with it. It used to be private to `ContentView`, where none of this could be
/// asserted; the cases below are the ones that crash the app at launch when it is wrong.
struct NoteSelectionTests {

    @Test(arguments: [-1, -42, Int.min])
    func aNegativeSelectionBecomesTheFirstNote(stored: Int) {
        #expect(NoteSelection.clamped(stored, noteCount: AppConstants.noteCount) == 0)
    }

    /// `noteCount` itself is the case a `<=`/`<` slip lets through, which a test using only a
    /// wild value jumps clean over.
    @Test(arguments: [AppConstants.noteCount, AppConstants.noteCount + 1, 999, Int.max])
    func aSelectionPastTheEndBecomesTheLastNote(stored: Int) {
        #expect(
            NoteSelection.clamped(stored, noteCount: AppConstants.noteCount)
                == AppConstants.noteCount - 1)
    }

    @Test(arguments: 0..<AppConstants.noteCount)
    func aSelectionInRangeIsLeftAlone(stored: Int) {
        #expect(NoteSelection.clamped(stored, noteCount: AppConstants.noteCount) == stored)
    }

    /// The count is the array in hand, not `AppConstants.noteCount`: a store that has not
    /// finished seeding is the state `ContentView` renders its "Initializing" branch for, and
    /// the clamp must not answer with an index that array cannot serve.
    @Test(arguments: [-1, 0, 3])
    func anEmptyNotesArrayCannotBeIndexed(stored: Int) {
        #expect(NoteSelection.clamped(stored, noteCount: 0) == 0)
    }

    @Test func aShorterNotesArrayBoundsTheSelection() {
        #expect(NoteSelection.clamped(6, noteCount: 3) == 2)
    }

    /// `store` and `@AppStorage` have to name the same key or ⌘1–⌘7 would write somewhere the
    /// view never reads. Nothing else in the app touches the key directly.
    @Test func storeWritesTheSharedKey() throws {
        let scratch = try ScratchDefaults(name: "NoteSelectionTests")

        NoteSelection.store(4, in: scratch.defaults)

        #expect(scratch.defaults.integer(forKey: AppConstants.selectedNoteIndexKey) == 4)
    }
}
