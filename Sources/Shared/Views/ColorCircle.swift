import SwiftUI

/// One note in the switcher: a coloured circle, numbered when it is the one showing.
///
/// This control is the app's navigation, so it never relies on colour alone to say which note is
/// showing or whether it has content.
struct ColorCircle: View {
    let index: Int
    let assignedColor: Color
    let isEmpty: Bool

    @Binding var selectedNoteIndex: Int

    /// The system's own answer to "colour is not enough": when set, every circle is numbered.
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    /// The selection spring is exactly the shape this setting exists to suppress, mild or not.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The switcher's own size, deliberately not derived from `defaultFontSize`: nothing in this
    /// row depends on how big the editor text below it is.
    private static let diameter: CGFloat = 19.2

    /// The number on the selected circle, as a fraction of the diameter above.
    private static let numberScale: CGFloat = 0.8

    private let lineWidth: CGFloat = 3

    #if os(macOS)
        /// Fixed, because the panel is a menubar popover built around these sizes.
        private let size = Self.diameter
    #else
        /// Scaled: iOS text size is the user's to set, and this row is the only way to switch
        /// notes there.
        @ScaledMetric(relativeTo: .body) private var size = Self.diameter
    #endif

    var body: some View {
        let isSelected = selectedNoteIndex == index

        // A `Button` rather than `onTapGesture`: nothing here reads a tap's location or count, and
        // a gesture is not an activation to assistive technology.
        Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.6)) {
                selectedNoteIndex = index
            }
        } label: {
            circle(isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .chromeControl()
        // Only the selected circle is numbered, so without this the rest reach assistive
        // technology as identical unnamed shapes.
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

            // In the note's own colour on an unselected circle, which has no fill behind it for
            // white to read against.
            if isSelected || differentiateWithoutColor {
                Text("\(index + 1)")
                    .font(
                        .system(size: size * Self.numberScale, weight: .bold)
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
