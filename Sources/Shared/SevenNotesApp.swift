import SwiftUI
import SwiftData

@main
struct SevenNotesApp: App {
    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([NoteItem.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])

            // Seed database
            let context = container.mainContext
            let fetchDescriptor = FetchDescriptor<NoteItem>()
            let existingNotes = try context.fetch(fetchDescriptor)

            if existingNotes.count < 7 {
                let existingIds = Set(existingNotes.map { $0.id })
                for i in 0..<7 {
                    if !existingIds.contains(i) {
                        let newItem = NoteItem(id: i)
                        context.insert(newItem)
                    }
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

    init() {
        // AppInitializer logic is now handled in sharedModelContainer initialization
    }

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
        .modelContainer(SevenNotesApp.sharedModelContainer)
        #endif
    }
}
