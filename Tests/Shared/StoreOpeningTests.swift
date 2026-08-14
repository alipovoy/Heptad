import Foundation
import SwiftData
import Testing

@testable import Heptad

/// What launch does with the file holding all seven notes.
///
/// One case each way, because the interesting half is the one that used to be a `fatalError`: a
/// store this app cannot open is a crash on every launch, forever, in a menubar app whose icon
/// would then simply do nothing.
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
