import Foundation
import SwiftData
import Testing

@testable import Heptad

/// Seeding the seven notes at launch.
///
/// The interesting case is a store that already holds some of them — an install interrupted
/// partway, or a store carried over from a build with a different count. Seeding has to top that
/// up by id, because `NoteItem.id` is `.unique`: re-inserting an id that is already there is an
/// upsert, so a seed that counted instead of checking ids would not add stray rows, it would
/// overwrite notes the user had written in.
///
/// Every test runs against its own in-memory store, so the developer's real notes are never
/// opened, let alone seeded.
@MainActor
struct NoteSeedingTests {

    private func inMemoryContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: NoteItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func storedIds(_ context: ModelContext) throws -> [Int] {
        try context.fetch(FetchDescriptor<NoteItem>()).map(\.id).sorted()
    }

    @Test func anEmptyStoreGetsTheWholeSet() throws {
        let context = try inMemoryContext()

        try HeptadApp.seed(context)

        let ids = try storedIds(context)
        #expect(ids == Array(0..<AppConstants.noteCount))
    }

    /// The case the id check exists for: the missing ids come back, and the ones already there
    /// are not duplicated. Note 6 is deliberately present while 1, 2 and 4 are missing, so a seed
    /// that appended from the end rather than filling gaps would show up here.
    @Test func aPartialStoreIsToppedUpByIdRatherThanCount() throws {
        let context = try inMemoryContext()
        for id in [0, 3, 5, 6] { context.insert(NoteItem(id: id, text: "written in")) }

        try HeptadApp.seed(context)

        let ids = try storedIds(context)
        #expect(ids == Array(0..<AppConstants.noteCount))
    }

    /// What a bad top-up costs. Seeding runs on every launch, so a note that survived one launch
    /// has to survive all of them — and `.unique` means the failure is silent overwriting rather
    /// than a visible duplicate.
    @Test func seedingLeavesAnAlreadyWrittenNoteAlone() throws {
        let context = try inMemoryContext()
        context.insert(NoteItem(id: 3, text: "pass: rotate-me", isPlainText: true))

        try HeptadApp.seed(context)

        let notes = try context.fetch(FetchDescriptor<NoteItem>())
        let restored = try #require(notes.first { $0.id == 3 })
        #expect(restored.text == "pass: rotate-me", "Seeding must never write over a note")
        #expect(restored.isPlainText, "or reset how it is displayed")
    }

    /// Seven rows is not the same as these seven notes. A store with a hole in it and a stray id
    /// beside it has the right *count*, and a count check in front of the loop returned early —
    /// so the hole was never filled, on this launch or any later one.
    @Test func aStoreWithTheRightCountAndTheWrongIdsIsStillRepaired() throws {
        let context = try inMemoryContext()
        for id in [0, 1, 2, 4, 5, 6, 9] { context.insert(NoteItem(id: id, text: "note \(id)")) }

        try HeptadApp.seed(context)

        let ids = try storedIds(context)
        #expect(ids.contains(3), "The missing note comes back")
        #expect(Set(0..<AppConstants.noteCount).isSubset(of: Set(ids)))
        #expect(ids.contains(9), "and a row this app does not address is not deleted to make room")
    }

    /// A store holding more than the set — what a build with a higher `noteCount` leaves behind —
    /// is seeded like any other. The extras are the view's problem, not the seeder's.
    @Test func aStoreHoldingMoreThanTheSetIsStillSeeded() throws {
        let context = try inMemoryContext()
        for id in 0...AppConstants.noteCount { context.insert(NoteItem(id: id, text: "note \(id)")) }

        try HeptadApp.seed(context)

        #expect(try storedIds(context) == Array(0...AppConstants.noteCount))
    }

    /// A full store takes the early return — the state every launch after the first is in.
    @Test func afullStoreIsLeftAsItIs() throws {
        let context = try inMemoryContext()
        for id in 0..<AppConstants.noteCount {
            context.insert(NoteItem(id: id, text: "note \(id)"))
        }

        try HeptadApp.seed(context)

        let notes = try context.fetch(FetchDescriptor<NoteItem>())
        #expect(notes.count == AppConstants.noteCount)
        #expect(notes.allSatisfy { $0.text == "note \($0.id)" })
    }

    @Test func seedingTwiceIsTheSameAsSeedingOnce() throws {
        let context = try inMemoryContext()

        try HeptadApp.seed(context)
        try HeptadApp.seed(context)

        let ids = try storedIds(context)
        #expect(ids == Array(0..<AppConstants.noteCount))
    }
}
