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

            // Seed database
            let context = container.mainContext
            let fetchDescriptor = FetchDescriptor<NoteItem>()
            if try context.fetchCount(fetchDescriptor) < AppConstants.noteCount {
                let existingIds = Set(try context.fetch(fetchDescriptor).map(\.id))
                for noteId in 0..<AppConstants.noteCount where !existingIds.contains(noteId) {
                    context.insert(NoteItem(id: noteId, modifiedAt: .now))
                }
                try context.save()
            }

            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

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
