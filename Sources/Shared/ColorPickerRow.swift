import SwiftUI

/// Shared component for selecting the current note color.
struct ColorPickerRow: View {
    @Binding var selectedNoteIndex: Int
    let colors: [Color]
    let notes: [NoteItem]

    var body: some View {
        HStack(spacing: AppConstants.Layout.defaultSpacing) {
            ForEach(notes.indices, id: \.self) { index in
                ColorCircle(
                    index: index,
                    assignedColor: colors[index],
                    isEmpty: notes[index].isEmpty,
                    title: NoteTitleCache.shared.title(for: notes[index]),
                    selectedNoteIndex: $selectedNoteIndex
                )
            }
        }
    }
}
