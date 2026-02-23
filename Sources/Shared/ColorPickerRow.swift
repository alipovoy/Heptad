import SwiftUI

/// Shared component for selecting the current note color.
struct ColorPickerRow: View {
    @Binding var selectedNoteIndex: Int
    let colors: [Color]

    var body: some View {
        let spacing: CGFloat = AppConstants.UI.defaultSpacing
        HStack(spacing: spacing) {
            ForEach(0..<7, id: \.self) { index in
                ColorCircle(index: index, color: colors[index], selectedNoteIndex: $selectedNoteIndex)
            }
        }
    }
}
