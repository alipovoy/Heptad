import SwiftData
import SwiftUI

/// Main root view for the application.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \NoteItem.id) private var notes: [NoteItem]
    @AppStorage("selectedNoteIndex") private var selectedNoteIndex = 0
    @State private var textStats: TextStats = .zero

    static let colors: [Color] = [.red, .orange, .yellow, .green, .cyan, .blue, .purple]

    #if os(macOS)
        private static let willTerminateNotification = NSApplication.willTerminateNotification
    #else
        private static let willTerminateNotification = UIApplication.willTerminateNotification
    #endif

    var body: some View {
        Group {
            if notes.count == AppConstants.noteCount {
                VStack(spacing: 0) {
                    #if os(macOS)
                        macOSTitleBar

                        MacRichTextEditor(notes: notes, selectedNoteIndex: $selectedNoteIndex, textStats: $textStats)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(backgroundFill)
                    #else
                        ColorPickerRow(
                            selectedNoteIndex: $selectedNoteIndex, colors: Self.colors,
                            notes: notes
                        )
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)

                        IOSRichTextEditor(notes: notes, selectedNoteIndex: $selectedNoteIndex, textStats: $textStats)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    #endif

                    TextStatisticsBar(stats: textStats, color: Self.colors[selectedNoteIndex])
                        .background(backgroundFill)
                }
                #if os(macOS)
                    .frame(minWidth: 320, minHeight: 200)
                    .ignoresSafeArea(.all, edges: .top)
                #else
                    .background(backgroundFill)
                #endif
            } else {
                ProgressView("Initializing notes...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background || newPhase == .inactive {
                flushPendingSaves()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Self.willTerminateNotification)) { _ in
            flushPendingSaves()
        }
    }

    private func flushPendingSaves() {
        NotificationCenter.default.post(name: .flushPendingSaves, object: nil)
    }

    private var backgroundFill: some View {
        Self.colors[selectedNoteIndex].opacity(0.1)
            .ignoresSafeArea(edges: [.bottom, .leading, .trailing])
    }

    #if os(macOS)
        private var macOSTitleBar: some View {
            HStack {
                Button(action: {
                    NSApp.keyWindow?.performClose(nil)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
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
            .padding(.top, 5)
            .padding(.bottom, 5)
        }
    #endif
}

struct TextStatisticsBar: View {
    let stats: TextStats
    let color: Color

    var body: some View {
        Text("\(stats.lines) Lines ⋅ \(stats.words) Words ⋅ \(stats.characters) Characters")
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.2))
            .foregroundStyle(.secondary)  // Vivid text color relying on the background
    }
}
