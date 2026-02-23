import SwiftUI
import SwiftData

/// Main root view for the application.
/// Routes the UI to the OS-specific implementation to avoid macro clutter in view builders.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \NoteItem.id) private var notes: [NoteItem]
    @AppStorage("selectedNoteIndex") private var selectedNoteIndex = 0

    static let colors: [Color] = [.red, .orange, .yellow, .green, .cyan, .blue, .purple]

    var body: some View {
        Group {
            if notes.count == 7 {
                #if os(macOS)
                MacContentView(
                    notes: notes,
                    selectedNoteIndex: $selectedNoteIndex,
                    colors: Self.colors
                )
                #else
                IOSContentView(
                    notes: notes,
                    selectedNoteIndex: $selectedNoteIndex,
                    colors: Self.colors
                )
                #endif
            } else {
                ProgressView("Initializing notes...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
