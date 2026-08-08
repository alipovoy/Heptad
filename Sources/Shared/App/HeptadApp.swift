import SwiftData
import SwiftUI

@main
struct HeptadApp: App {
    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([NoteItem.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        ensureApplicationSupportDirectoryExists()

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            try Self.seed(container.mainContext)
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    /// Fills in whichever of the seven notes the store does not already hold.
    ///
    /// A top-up rather than a create, and by id rather than by count. The notes are addressed by
    /// id everywhere — ⌘1–⌘7, the palette, the stored selection — so a store missing note 3 needs
    /// note 3 back, not a seventh note appended under whatever id came next. `id` is `.unique`,
    /// so getting this wrong does not merely add rows: re-inserting an id that is already there
    /// upserts, and the note's text goes with it.
    ///
    /// Runs on every launch, so leaving what is already there untouched is the whole contract.
    ///
    /// Lifted out of the container above purely so it can be tested: the partial-store case is
    /// the one that matters and it cannot be arranged against the app's own on-disk store.
    static func seed(_ context: ModelContext) throws {
        let fetchDescriptor = FetchDescriptor<NoteItem>()
        guard try context.fetchCount(fetchDescriptor) < AppConstants.noteCount else { return }

        let existingIds = Set(try context.fetch(fetchDescriptor).map(\.id))
        for noteId in 0..<AppConstants.noteCount where !existingIds.contains(noteId) {
            context.insert(NoteItem(id: noteId, modifiedAt: .now))
        }
        try context.save()
    }

    /// Creates `Library/Application Support` before the store beneath it is opened.
    ///
    /// The default store lives at `…/Library/Application Support/default.store`, and on a
    /// container where that directory does not exist yet — a fresh iOS app container, first
    /// launch of a real install — the first `addPersistentStore` fails with Cocoa error 512.
    /// CoreData recovers by creating the directory and retrying, but only after dumping a
    /// filesystem diagnostic for every path component: hundreds of `CoreData: error` lines,
    /// plus a retry on the launch path. macOS never hits it; `~/Library/Application Support`
    /// always exists there.
    ///
    /// The result is deliberately discarded: this is the retry being pre-empted, and a failure
    /// here leaves exactly the behaviour that shipped before.
    private static func ensureApplicationSupportDirectoryExists() {
        _ = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }

    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    var body: some Scene {
        #if os(macOS)
        // macOS windowing is handled entirely by AppDelegate (menubar popup).
        // Providing a Settings scene (rather than WindowGroup) prevents SwiftUI
        // from auto-showing a main window at launch.
        Settings {
            EmptyView()
        }
        #else
        WindowGroup {
            ContentView()
        }
        .modelContainer(Self.sharedModelContainer)
        #endif
    }
}
