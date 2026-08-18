import Foundation
import SwiftData
import Testing

@testable import Heptad

/// A `NoteItem` as an older build of the app defined it: content in `rtfData`, which #118 removed.
///
/// Nested so the name does not collide with the shipping model's. SwiftData names the entity after
/// the unqualified class name, so to the store on disk this is `NoteItem` — which is what makes the
/// mismatch below a mismatch rather than a second table.
enum LegacySchema {
    @Model final class NoteItem {
        var id: Int = 0
        var rtfData: Data?

        init(id: Int, rtfData: Data?) {
            self.id = id
            self.rtfData = rtfData
        }
    }
}

/// What launch does with the file holding all seven notes.
///
/// A store this app cannot open was a `fatalError` — a crash on every launch, forever, in a menubar
/// app whose icon would then do nothing. The third case is a file an older schema wrote, which is
/// how #118 lost every note.
@MainActor
struct StoreOpeningTests {

    private func scratchStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "heptad-\(UUID().uuidString).store")
    }

    @Test func aStoreThatCannotBeOpenedStillLeavesAWorkingApp() throws {
        let url = scratchStoreURL()
        try Data("this is not a database".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let schema = Schema([NoteItem.self])
        let opening = HeptadApp.opening(
            for: schema, configuration: ModelConfiguration(schema: schema, url: url))

        #expect(opening.container.configurations.first?.isStoredInMemoryOnly == true)
        #expect(
            try opening.container.mainContext.fetch(FetchDescriptor<NoteItem>()).count
                == AppConstants.noteCount,
            "and the seven notes are there to be written in, for this session at least")
        #expect(
            opening.health == .ephemeral,
            "and the app is told, because those seven notes are indistinguishable from the store")
    }

    /// The store opens and holds the notes, but will not take a write — a read-only or full
    /// volume. `allowsSave: false` is that store without needing one.
    ///
    /// Seeded with note 0 alone first, because `seed` is a top-up: against a complete store it
    /// writes nothing, reaches no `save()`, and a read-only file is indistinguishable from a
    /// healthy one at launch. That gap is real and is why `ContentView` reports its own failed
    /// saves — this test covers the launch that does try to write.
    ///
    /// The failure used to be a bare `try?`, so a launch onto a full disk looked like any other.
    @Test func aStoreThatWillNotTakeAWriteIsReportedAsNotSaving() throws {
        let url = scratchStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let schema = Schema([NoteItem.self])
        let writable = try ModelContainer(
            for: schema, configurations: ModelConfiguration(schema: schema, url: url))
        writable.mainContext.insert(NoteItem(id: 0, modifiedAt: .now))
        try writable.mainContext.save()

        let opening = HeptadApp.opening(
            for: schema,
            configuration: ModelConfiguration(schema: schema, url: url, allowsSave: false))

        #expect(opening.health == .notSaving)
        #expect(
            opening.container.configurations.first?.isStoredInMemoryOnly == false,
            "the file itself is still the one in use — the notes in it are the user's own")
        #expect(
            opening.container.mainContext.hasChanges,
            "and the six notes the save could not write are still in the context, to be shown")
    }

    /// A store written by an older schema — the one thing no other test does, since every other one
    /// builds a fresh container whose schema on disk matches the binary's.
    ///
    /// Asserted as decided in D3 (no versioned schema, no migration plan): the app opens the file,
    /// seeds the seven notes, does not crash, and content that lived only in a dropped property is
    /// gone.
    @Test func aStoreWrittenByAnOlderSchemaStillOpens() throws {
        let url = scratchStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let legacySchema = Schema([LegacySchema.NoteItem.self])
        let legacy = try ModelContainer(
            for: legacySchema,
            configurations: ModelConfiguration(schema: legacySchema, url: url))
        legacy.mainContext.insert(
            LegacySchema.NoteItem(id: 0, rtfData: Data("a note nobody can read now".utf8)))
        try legacy.mainContext.save()

        let schema = Schema([Heptad.NoteItem.self])
        let opening = HeptadApp.opening(
            for: schema, configuration: ModelConfiguration(schema: schema, url: url))
        let notes = try opening.container.mainContext.fetch(FetchDescriptor<Heptad.NoteItem>())

        #expect(
            opening.health == .healthy,
            "the file itself opened — otherwise this would be the fallback above, not a migration")
        #expect(notes.count == AppConstants.noteCount, "the app comes up with its seven notes")
        #expect(
            notes.allSatisfy { $0.text.isEmpty },
            "and nothing that was in `rtfData` came with them")
    }

    @Test func aStoreThatOpensIsTheOneUsed() throws {
        let url = scratchStoreURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let schema = Schema([NoteItem.self])
        let opening = HeptadApp.opening(
            for: schema, configuration: ModelConfiguration(schema: schema, url: url))

        #expect(opening.health == .healthy)
        #expect(opening.container.configurations.first?.isStoredInMemoryOnly == false)
        #expect(opening.container.configurations.first?.url == url)
        #expect(
            try opening.container.mainContext.fetch(FetchDescriptor<NoteItem>()).count
                == AppConstants.noteCount)
    }
}
