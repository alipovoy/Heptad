import SwiftUI

/// Shared component for selecting the current note color.
struct ColorPickerRow: View {
    @Binding var selectedNoteIndex: Int
    let notes: [NoteItem]

    var body: some View {
        HStack(spacing: AppConstants.Layout.defaultSpacing) {
            ForEach(notes.indices, id: \.self) { index in
                ColorCircle(
                    index: index,
                    assignedColor: NotePalette.colors[index],
                    isEmpty: notes[index].isEmpty,
                    title: NoteTitleCache.shared.title(for: notes[index]),
                    selectedNoteIndex: $selectedNoteIndex
                )
            }
        }
    }
}

/// The row as it is normally seen: mostly empty notes, two with content, one of them selected.
#Preview("Mixed row") {
    ColorPickerRow(selectedNoteIndex: .constant(3), notes: PreviewFixtures.notes())
        .padding()
}
