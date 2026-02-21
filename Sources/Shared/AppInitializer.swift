import Foundation
import SwiftData

@MainActor
final class AppInitializer {
    static let shared = AppInitializer()
    private var isInitialized = false

    private init() {}

    func initialize(modelContainer: ModelContainer) {
        guard !isInitialized else { return }
        isInitialized = true

        let context = modelContainer.mainContext
        seedDatabaseIfNeeded(context: context)
    }

    private func seedDatabaseIfNeeded(context: ModelContext) {
        do {
            let fetchDescriptor = FetchDescriptor<NoteItem>()
            let existingNotes = try context.fetch(fetchDescriptor)

            if existingNotes.count >= 7 { return }

            let existingIds = Set(existingNotes.map { $0.id })

            for i in 0..<7 {
                if !existingIds.contains(i) {
                    let newItem = NoteItem(id: i)
                    context.insert(newItem)
                }
            }

            try context.save()
        } catch {
            print("Failed to seed database: \(error)")
        }
    }
}
