import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \NoteItem.id) private var notes: [NoteItem]
    @AppStorage("selectedNoteIndex") private var selectedNoteIndex = 0

    let colors: [Color] = [.red, .orange, .yellow, .green, .cyan, .blue, .purple]

    var body: some View {
        ZStack {
            if notes.count == 7 {
                colors[selectedNoteIndex].opacity(0.15)
                    .ignoresSafeArea(edges: [.bottom, .leading, .trailing])
            }

            VStack(spacing: 0) {
                #if os(iOS)
                // Tab Bar (iOS)
                colorPickerRow
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                #endif

                // Editor Area
                if notes.count == 7 {
                    let note = notes[selectedNoteIndex]
                    #if os(macOS)
                    MacRichTextEditor(note: note)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .id(note.id)
                    #else
                    IOSRichTextEditor(note: note)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .id(note.id)
                    #endif
                } else {
                    ProgressView("Initializing notes...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        #if os(macOS)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    NSApp.keyWindow?.orderOut(nil)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close window")
            }

            ToolbarItem(placement: .principal) {
                colorPickerRow
            }
        }
        #endif
        .onAppear {
            initializeIfNeeded()
        }
    }

    @ViewBuilder
    private var colorPickerRow: some View {
        let spacing: CGFloat = 15
        HStack(spacing: spacing) {
            ForEach(0..<7, id: \.self) { index in
                colorCircle(index: index)
            }
        }
    }

    @ViewBuilder
    private func colorCircle(index: Int) -> some View {
        let size: CGFloat = 16
        let scale: CGFloat = 1.2
        let ringOpacity = 0.7
        let lineWidth: CGFloat = 2
        let ringScale: CGFloat = 1.2

        Circle()
            .fill(colors[index])
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

    private func initializeIfNeeded() {
        if notes.count >= 7 {
            return
        }

        // Find existing IDs
        let existingIds = Set(notes.map { $0.id })

        // Create missing
        for i in 0..<7 {
            if !existingIds.contains(i) {
                let newItem = NoteItem(id: i)
                modelContext.insert(newItem)
            }
        }

        try? modelContext.save()
    }
}
