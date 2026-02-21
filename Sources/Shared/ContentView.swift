import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \NoteItem.id) private var notes: [NoteItem]
    @AppStorage("selectedNoteIndex") private var selectedNoteIndex = 0

    static let colors: [Color] = [.red, .orange, .yellow, .green, .cyan, .blue, .purple]

    var body: some View {
        ZStack {
            if notes.count == 7 {
                Self.colors[selectedNoteIndex].opacity(0.15)
                    .ignoresSafeArea(edges: [.bottom, .leading, .trailing])
            }

            VStack(spacing: 0) {
                #if os(iOS)
                // Tab Bar (iOS)
                colorPickerRow
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                #endif

                // Editor Area
                if notes.count == 7 {
                    let note = notes[selectedNoteIndex]
                    #if os(macOS)
                    MacRichTextEditor(note: note)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .id(note.id)
                    #else
                    IOSRichTextEditor(note: note)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .id(note.id)
                    #endif
                } else {
                    ProgressView("Initializing notes...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 320, minHeight: 200)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    NSApp.keyWindow?.orderOut(nil)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close window")
            }

            ToolbarItem(placement: .principal) {
                colorPickerRow
            }
        }
        #endif
    }

    @ViewBuilder
    private var colorPickerRow: some View {
        let spacing: CGFloat = AppConstants.UI.defaultSpacing
        HStack(spacing: spacing) {
            ForEach(0..<7, id: \.self) { index in
                ColorCircle(index: index, color: Self.colors[index], selectedNoteIndex: $selectedNoteIndex)
            }
        }
    }

}
