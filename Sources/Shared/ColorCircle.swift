import SwiftUI

struct ColorCircle: View {
    let index: Int
    let assignedColor: Color
    let isEmpty: Bool
    @Binding var selectedNoteIndex: Int

    private var size: CGFloat {
        AppConstants.UI.defaultFontSize * AppConstants.UI.ColorCircle.sizeMultiplier
    }
    private var lineWidth: CGFloat {
        AppConstants.UI.ColorCircle.strokeLineWidth
    }

    var body: some View {
        let isSelected = selectedNoteIndex == index

        ZStack {
            // Background fill
            if isSelected {
                Circle().fill(assignedColor)
            } else if isEmpty {
                Circle().fill(Color.gray)
            } else {
                Circle().fill(Color.clear)
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
                            size: size * AppConstants.UI.ColorCircle.selectedNumberFontScale,
                            weight: .bold)
                    )
                    .foregroundColor(.white)
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
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                selectedNoteIndex = index
            }
        }
    }
}
