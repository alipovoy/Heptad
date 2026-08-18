import SwiftUI

/// One note in the switcher: a coloured circle, numbered when it is the one showing.
///
/// This control *is* the app's navigation, so what it says about itself matters more than it
/// would for decoration. The number, the selection and "has content" all used to be carried by
/// colour alone — the same hue at seven values, with the closest pair a tenth of the RGB cube
/// apart, and a label that read "Note 3" whether note 3 was the one on screen or not.
struct ColorCircle: View {
    let index: Int
    let assignedColor: Color
    let isEmpty: Bool

    @Binding var selectedNoteIndex: Int

    /// The system's own answer to "colour is not enough". Turning it on numbers every circle
    /// rather than only the selected one, which is the same argument the label below makes.
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    #if os(macOS)
        /// Fixed, because the panel is a menubar popover built around these sizes.
        private let size =
            AppConstants.Layout.defaultFontSize * AppConstants.Layout.ColorCircle.sizeMultiplier
    #else
        /// Scaled, because iOS is a full-screen window whose text size the user sets — and this
        /// row is the note switcher, the one control there is no keyboard alternative to on iOS.
        @ScaledMetric(relativeTo: .body) private var size =
            AppConstants.Layout.defaultFontSize * AppConstants.Layout.ColorCircle.sizeMultiplier
    #endif

    private var lineWidth: CGFloat {
        AppConstants.Layout.ColorCircle.strokeLineWidth
    }

    var body: some View {
        let isSelected = selectedNoteIndex == index

        // A `Button` rather than `onTapGesture`: nothing here reads a tap's location or count,
        // and a gesture is not an activation to assistive technology. macOS has ⌘1–⌘7 to fall
        // back on; iOS has nothing else at all.
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                selectedNoteIndex = index
            }
        } label: {
            circle(isSelected: isSelected)
        }
        .buttonStyle(.plain)
        // The number is drawn on the selected circle alone, so every other one would otherwise
        // reach assistive technology as an unnamed shape — and all seven as identical ones.
        .accessibilityLabel("Note \(index + 1)")
        .accessibilityValue(isEmpty ? "Empty" : "Has content")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func circle(isSelected: Bool) -> some View {
        ZStack {
            // Background fill
            if isSelected {
                Circle().fill(assignedColor)
            } else if isEmpty {
                Circle().fill(Color.gray)
            }

            // Stroke and gradient for unselected, non-empty circle
            if !isSelected && !isEmpty {
                Circle()
                    .stroke(assignedColor, lineWidth: lineWidth)
                    .frame(width: size - lineWidth, height: size - lineWidth)

                LinearGradient(
                    colors: [.black.opacity(0.25), .white.opacity(0.25)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .mask(
                    Circle()
                        .stroke(Color.white, lineWidth: lineWidth)
                        .frame(width: size - lineWidth, height: size - lineWidth)
                )
            }

            // The number: on the selected circle always, and on every circle when the user has
            // asked not to be told things by colour. Drawn in the note's own colour where there
            // is no fill behind it to read against.
            if isSelected || differentiateWithoutColor {
                Text("\(index + 1)")
                    .font(
                        .system(
                            size: size * AppConstants.Layout.ColorCircle.selectedNumberFontScale,
                            weight: .bold)
                    )
                    .foregroundStyle(isSelected || isEmpty ? Color.white : assignedColor)
            }

            // Overlay gradient for selected or empty circle
            if isSelected || isEmpty {
                LinearGradient(
                    colors: [.black.opacity(0.15), .white.opacity(0.25)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(Circle())
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
    }
}

/// Every state the circle has: selected — which is also the only one with the number overlay —
/// unselected with content, and empty.
#Preview("States") {
    HStack(spacing: AppConstants.Layout.defaultSpacing) {
        ColorCircle(index: 0, assignedColor: .red, isEmpty: false, selectedNoteIndex: .constant(0))
        ColorCircle(
            index: 1, assignedColor: .orange, isEmpty: false, selectedNoteIndex: .constant(0))
        ColorCircle(
            index: 2, assignedColor: .yellow, isEmpty: true, selectedNoteIndex: .constant(0))
    }
    .padding()
}
