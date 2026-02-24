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

        Circle()
            .fill(fillColor(isSelected: isSelected))
            .frame(width: size, height: size)
            .overlay(circleStroke(isSelected: isSelected))
            .overlay(selectedNoteNumber(isSelected: isSelected))
            .overlay(circleGradient(isSelected: isSelected))
            .contentShape(Circle())
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    selectedNoteIndex = index
                }
            }
    }

    private func circleGradient(isSelected: Bool) -> some View {
        Group {
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
    }

    private func fillColor(isSelected: Bool) -> Color {
        if isSelected {
            return assignedColor
        }
        if isEmpty {
            return .gray
        }
        return .clear
    }

    private func selectedNoteNumber(isSelected: Bool) -> some View {
        Group {
            if isSelected {
                Text("\(index + 1)")
                    .font(.system(size: size * AppConstants.UI.ColorCircle.selectedNumberFontScale, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .frame(width: size, height: size)
    }

    private func circleStroke(isSelected: Bool) -> some View {
        Group {
            if !isSelected && !isEmpty {
                ZStack {
                    Circle()
                        .stroke(assignedColor, lineWidth: lineWidth)
                        .frame(width: size - lineWidth, height: size - lineWidth)
                    LinearGradient(
                        colors: [.black.opacity(0.25), .white.opacity(0.25)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: size, height: size)
                    .mask(
                        Circle()
                            .stroke(Color.white, lineWidth: lineWidth)
                            .frame(width: size - lineWidth, height: size - lineWidth)
                    )
                }
            }
        }
        .frame(width: size, height: size)
    }

}
