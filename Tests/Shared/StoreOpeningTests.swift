import Foundation
import SwiftData
import Testing

@testable import Heptad

/// A `NoteItem` as an older build of the app defined it: content in `rtfData`, which #118 removed.
///
/// Nested so the name does not collide with the shipping model's — SwiftData names the entity after
/// the unqualified class name, so to the store on disk this *is* `NoteItem`, which is what makes the
/// schema mismatch below a mismatch rather than a second table.
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
/// One case each way, because the interesting half is the one that used to be a `fatalError`: a
/// store this app cannot open is a crash on every launch, forever, in a menubar app whose icon
/// would then simply do nothing. And one for a file an older schema wrote, which is how #118 lost
/// every note.
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
        let container = HeptadApp.container(
            for: schema, configuration: ModelConfiguration(schema: schema, url: url))

        #expect(container.configurations.first?.isStoredInMemoryOnly == true)
        #expect(
            try container.mainContext.fetch(FetchDescriptor<NoteItem>()).count
                == AppConstants.noteCount,
            "and the seven notes are there to be written in, for this session at least")
    }

    /// A store written by an older schema, which is the #118 case and the one thing no test in the
    /// suite had ever done: every other one builds a fresh container, so the schema on disk always
    /// matched the schema in the binary.
    ///
    /// What is asserted is what the owner decided (D3: no versioned schema, no migration plan): the
    /// app opens the file, seeds the seven notes, and does not crash. Content that lived only in a
    /// property the current schema does not have is gone, and this test says so out loud rather
    /// than leaving it to be discovered a second time.
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
        let container = HeptadApp.container(
            for: schema, configuration: ModelConfiguration(schema: schema, url: url))
        let notes = try container.mainContext.fetch(FetchDescriptor<Heptad.NoteItem>())

        #expect(
            container.configurations.first?.isStoredInMemoryOnly == false,
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
        let container = HeptadApp.container(
            for: schema, configuration: ModelConfiguration(schema: schema, url: url))

        #expect(container.configurations.first?.isStoredInMemoryOnly == false)
        #expect(container.configurations.first?.url == url)
        #expect(
            try container.mainContext.fetch(FetchDescriptor<NoteItem>()).count
                == AppConstants.noteCount)
    }
}
