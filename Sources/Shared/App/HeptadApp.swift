import OSLog
import SwiftData
import SwiftUI

/// The container the app runs on, together with what had to go wrong to get it.
///
/// One value rather than two: the health is only ever true of the container beside it, and the
/// pair is decided once, at launch, by `HeptadApp.opening(for:configuration:)`.
struct StoreOpening {
    let container: ModelContainer
    let health: StoreHealth
}

@main
struct HeptadApp: App {
    static let sharedStore: StoreOpening = {
        let schema = Schema([NoteItem.self])
        ensureApplicationSupportDirectoryExists()

        return opening(
            for: schema,
            configuration: ModelConfiguration(schema: schema, isStoredInMemoryOnly: false))
    }()

    /// The container alone, for the callers that only mount it or read a context off it.
    static var sharedModelContainer: ModelContainer { sharedStore.container }

    /// The health of `sharedStore`, in the form the views take. Built once, here, so that the two
    /// mount sites and the status-item menu are all looking at the same object.
    @MainActor static let sharedStatus = StoreStatus(sharedStore.health)

    /// The note store, or an in-memory stand-in that lasts the session when it cannot be opened.
    ///
    /// Not a `fatalError`: a store truncated by a power loss, left behind by a newer build, on a
    /// read-only or full volume, or needing a migration that will not run would otherwise crash
    /// every launch, with no recourse from inside the app.
    ///
    /// The failure is returned rather than only logged. Both fallbacks hand back a container that
    /// answers every query with seven notes, so nothing downstream can tell them from a healthy
    /// launch — see `StoreHealthBanner`, which is the only thing that tells the user.
    static func opening(for schema: Schema, configuration: ModelConfiguration) -> StoreOpening {
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])

            do {
                try seed(container.mainContext)
            } catch {
                // A store that opens but will not take a write still has the notes in it — not a
                // reason to hide them behind the stand-in below. The seeded rows stay in the
                // context unsaved, which is exactly what everything typed after them will do.
                log(error, "The note store would not take a write")
                return StoreOpening(container: container, health: .notSaving)
            }

            return StoreOpening(container: container, health: .healthy)
        } catch {
            log(error, "The note store could not be opened, running in memory")

            return StoreOpening(container: ephemeralContainer(for: schema), health: .ephemeral)
        }
    }

    private static func log(_ error: Error, _ message: String) {
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "Heptad", category: "store")
            .error("\(message): \(error)")
    }

    /// The stand-in. `try!` because reaching it means the schema itself cannot be built, which no
    /// store on disk can cause and no launch can recover from.
    private static func ephemeralContainer(for schema: Schema) -> ModelContainer {
        // swiftlint:disable:next force_try
        let container = try! ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        try? seed(container.mainContext)

        return container
    }

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
        // Ids alone: this runs on the launch path, and a plain fetch reads every note's `text` to
        // answer a question about seven integers.
        var descriptor = FetchDescriptor<NoteItem>()
        descriptor.propertiesToFetch = [\.id]

        let existingIds = Set(try context.fetch(descriptor).map(\.id))
        for noteId in 0..<AppConstants.noteCount where !existingIds.contains(noteId) {
            context.insert(NoteItem(id: noteId, modifiedAt: .now))
        }

        // Every launch after the first has nothing to add, and costs the fetch above alone.
        guard context.hasChanges else { return }
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
                .environment(Self.sharedStatus)
        }
        .modelContainer(Self.sharedStore.container)
        #endif
    }
}
