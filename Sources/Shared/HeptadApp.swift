import SwiftData
import SwiftUI

@main
struct HeptadApp: App {
    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([NoteItem.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])

            // Seed database
            let context = container.mainContext
            let fetchDescriptor = FetchDescriptor<NoteItem>()
            if try context.fetchCount(fetchDescriptor) < AppConstants.noteCount {
                let existingIds = Set(try context.fetch(fetchDescriptor).map(\.id))
                for i in 0..<AppConstants.noteCount where !existingIds.contains(i) {
                    context.insert(NoteItem(id: i))
                }
                try context.save()
            }

            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

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
        .modelContainer(HeptadApp.sharedModelContainer)
        #endif
    }
}
