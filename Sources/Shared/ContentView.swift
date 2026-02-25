import SwiftData
import SwiftUI

/// Main root view for the application.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \NoteItem.id) private var notes: [NoteItem]
    @AppStorage("selectedNoteIndex") private var selectedNoteIndex = 0

    static let colors: [Color] = [.red, .orange, .yellow, .green, .cyan, .blue, .purple]

    var body: some View {
        Group {
            if notes.count == 7 {
                ZStack {
                    Self.colors[selectedNoteIndex].opacity(0.15)
                        .ignoresSafeArea(edges: [.bottom, .leading, .trailing])

                    VStack(spacing: 0) {
                        #if os(macOS)
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
                                    selectedNoteIndex: $selectedNoteIndex, colors: Self.colors,
                                    notes: notes)

                                Spacer()

                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .opacity(0)
                                    .padding(.trailing, 14)
                            }
                            .padding(.top, 10)
                            .padding(.bottom, 8)
                            .background(Color.clear)
                        #else
                            ColorPickerRow(
                                selectedNoteIndex: $selectedNoteIndex, colors: Self.colors,
                                notes: notes
                            )
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                        #endif

                        #if os(macOS)
                            MacRichTextEditor(notes: notes, selectedNoteIndex: $selectedNoteIndex)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        #else
                            IOSRichTextEditor(note: notes[selectedNoteIndex])
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .id(notes[selectedNoteIndex].id)
                        #endif
                    }
                }
                #if os(macOS)
                    .frame(minWidth: 320, minHeight: 200)
                    .ignoresSafeArea(.all, edges: .top)
                #endif
            } else {
                ProgressView("Initializing notes...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
