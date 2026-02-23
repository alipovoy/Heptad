import SwiftUI
import SwiftData

#if os(macOS)
struct MacContentView: View {
    let notes: [NoteItem]
    @Binding var selectedNoteIndex: Int
    let colors: [Color]

    var body: some View {
        ZStack {
            if notes.count == 7 {
                colors[selectedNoteIndex].opacity(0.15)
                    .ignoresSafeArea(edges: [.bottom, .leading, .trailing])

                let note = notes[selectedNoteIndex]
                MacRichTextEditor(note: note)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(note.id)
            } else {
                ProgressView("Initializing notes...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
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
                ColorPickerRow(selectedNoteIndex: $selectedNoteIndex, colors: colors)
            }
        }
    }
}
#endif
