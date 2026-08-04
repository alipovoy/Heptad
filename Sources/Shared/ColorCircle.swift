import SwiftUI

struct ColorCircle: View {
    let index: Int
    let assignedColor: Color
    let isEmpty: Bool

    /// The note's first line, so the circles say which note they are without opening each one.
    let title: String

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
        // A tooltip on macOS; an accessibility hint everywhere else.
        .help(title)
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                selectedNoteIndex = index
            }
        }
    }
}
