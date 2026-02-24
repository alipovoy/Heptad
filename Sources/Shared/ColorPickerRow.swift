import SwiftUI

/// Shared component for selecting the current note color.
struct ColorPickerRow: View {
    @Binding var selectedNoteIndex: Int
    let colors: [Color]
    let notes: [NoteItem]

    var body: some View {
        let spacing: CGFloat = AppConstants.UI.defaultSpacing
        HStack(spacing: spacing) {
            ForEach(0..<7, id: \.self) { index in
                ColorCircle(
                    index: index,
                    assignedColor: colors[index],
                    isEmpty: notes[index].rtfData.isEmpty,
                    selectedNoteIndex: $selectedNoteIndex
                )
            }
        }
    }
}
