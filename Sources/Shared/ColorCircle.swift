import SwiftUI

struct ColorCircle: View {
    let index: Int
    let color: Color
    @Binding var selectedNoteIndex: Int

    var body: some View {
        let size: CGFloat = AppConstants.UI.defaultFontSize
        let scale: CGFloat = 1.2
        let ringOpacity = 0.7
        let lineWidth: CGFloat = 2
        let ringScale: CGFloat = 1.2

        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .scaleEffect(selectedNoteIndex == index ? scale : 1.0)
            .overlay(
                Circle()
                    .stroke(Color.primary.opacity(selectedNoteIndex == index ? ringOpacity : 0), lineWidth: lineWidth)
                    .scaleEffect(selectedNoteIndex == index ? ringScale : 1.0)
            )
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    selectedNoteIndex = index
                }
            }
    }
}
