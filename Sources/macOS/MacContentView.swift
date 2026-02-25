import SwiftData
import SwiftUI

#if os(macOS)
    struct MacContentView: View {
        let notes: [NoteItem]
        @Binding var selectedNoteIndex: Int
        let colors: [Color]

        var body: some View {
            VStack(spacing: 0) {
                // Custom Title Bar
                HStack {
                    Button(action: {
                        NSApp.keyWindow?.performClose(nil)
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .accessibilityLabel("Close window")
                    .padding(.leading, 14)

                    Spacer()

                    ColorPickerRow(
                        selectedNoteIndex: $selectedNoteIndex, colors: colors, notes: notes)

                    Spacer()

                    // Invisible placeholder to keep the ColorPickerRow centered
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .opacity(0)
                        .padding(.trailing, 14)
                }
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(Color.clear)  // allow window drag through the stack

                ZStack {
                    colors[selectedNoteIndex].opacity(0.15)
                        .ignoresSafeArea(edges: [.bottom, .leading, .trailing])

                    MacRichTextEditor(notes: notes, selectedNoteIndex: $selectedNoteIndex)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 320, minHeight: 200)
            .ignoresSafeArea(.all, edges: .top)
        }
    }
#endif
