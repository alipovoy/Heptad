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
                colors[selectedNoteIndex].opacity(0.15).ignoresSafeArea()
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
        .frame(minWidth: 300, minHeight: 400)
        #if os(macOS)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: {
                    NSApp.windows.first(where: { $0.isVisible && $0 is NSPanel })?.orderOut(nil)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary.opacity(0.6))
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
        #if os(macOS)
        let size: CGFloat = 16
        let spacing: CGFloat = 10
        let scale: CGFloat = 1.15
        let ringOpacity = 0.4
        let lineWidth: CGFloat = 2
        let ringScale: CGFloat = 1.0
        #else
        let size: CGFloat = 14
        let spacing: CGFloat = 8
        let scale: CGFloat = 1.2
        let ringOpacity = 0.3
        let lineWidth: CGFloat = 1.5
        let ringScale: CGFloat = 1.4
        #endif
        
        HStack(spacing: spacing) {
            ForEach(0..<7) { index in
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
        }
    }

    private func initializeIfNeeded() {
        if notes.count != 7 {
            // Clear existing if mismatch (e.g. during development)
            for note in notes {
                modelContext.delete(note)
            }
            for i in 0..<7 {
                let newItem = NoteItem(id: i, colorHex: "")
                modelContext.insert(newItem)
            }
            try? modelContext.save()
        }
    }
}
