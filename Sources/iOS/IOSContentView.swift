import SwiftUI
import SwiftData

#if os(iOS)
struct IOSContentView: View {
    let notes: [NoteItem]
    @Binding var selectedNoteIndex: Int
    let colors: [Color]

    var body: some View {
        ZStack {
            colors[selectedNoteIndex].opacity(0.15)
                .ignoresSafeArea(edges: [.bottom, .leading, .trailing])

            VStack(spacing: 0) {
                ColorPickerRow(selectedNoteIndex: $selectedNoteIndex, colors: colors)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)

                // Editor Area
                let note = notes[selectedNoteIndex]
                IOSRichTextEditor(note: note)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(note.id)
            }
        }
    }
}
#endif
