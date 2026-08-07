import SwiftUI

struct ColorCircle: View {
    let index: Int
    let assignedColor: Color
    let isEmpty: Bool

    @Binding var selectedNoteIndex: Int

    private var size: CGFloat {
        AppConstants.Layout.defaultFontSize * AppConstants.Layout.ColorCircle.sizeMultiplier
    }
    private var lineWidth: CGFloat {
        AppConstants.Layout.ColorCircle.strokeLineWidth
    }

    var body: some View {
        let isSelected = selectedNoteIndex == index

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

            // Number for selected circle
            if isSelected {
                Text("\(index + 1)")
                    .font(
                        .system(
                            size: size * AppConstants.Layout.ColorCircle.selectedNumberFontScale,
                            weight: .bold)
                    )
                    .foregroundStyle(.white)
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
        // The number is only drawn on the selected circle, so every other one would otherwise
        // reach assistive technology as an unnamed shape.
        .accessibilityLabel("Note \(index + 1)")
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                selectedNoteIndex = index
            }
        }
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
