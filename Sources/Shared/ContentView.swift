import SwiftData
import SwiftUI

/// Main root view for the application.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \NoteItem.id) private var notes: [NoteItem]
    @AppStorage(AppConstants.selectedNoteIndexKey) private var selectedNoteIndex = 0
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
                Button {
                    NSApp.keyWindow?.performClose(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: AppConstants.Layout.titleBarIconSize))
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

                // Balances the close button so the colour circles stay centred. The pin toggle
                // deliberately does not live here: pin.slash and pin.fill are different widths,
                // so toggling it nudged the circles sideways.
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: AppConstants.Layout.titleBarIconSize))
                    .hidden()  // Reserves the space without leaving it in the accessibility tree
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

    #if os(macOS)
        /// Read-only mirror of the window state WindowManager persists, so the pin button always
        /// shows the truth — including when the state changes by ⌘P or by dragging the panel away.
        @AppStorage(AppConstants.windowPinnedKey) private var isWindowPinned = false
    #endif

    var body: some View {
        HStack(spacing: 8) {
            Text("\(stats.lines) Lines ⋅ \(stats.words) Words ⋅ \(stats.characters) Characters")
                .font(
                    .system(
                        size: AppConstants.Layout.statisticsFontSize, weight: .medium,
                        design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)

            #if os(macOS)
                pinToggle
            #endif
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(color.opacity(0.2))
        .foregroundStyle(.secondary)  // Vivid text color relying on the background
    }

    #if os(macOS)
        /// Sized against the 11pt statistics text it sits beside, and left to inherit the bar's
        /// secondary foreground style in both states — outlined vs filled carries the meaning.
        private var pinToggle: some View {
            Button {
                // WindowManager owns and persists the state; this only asks it to flip.
                NotificationCenter.default.post(name: .toggleWindowPin, object: nil)
            } label: {
                Image(systemName: isWindowPinned ? "pin.fill" : "pin.slash")
                    .font(.system(size: AppConstants.Layout.pinToggleIconSize))
            }
            .buttonStyle(.plain)
            .focusable(false)
            .accessibilityLabel(isWindowPinned ? "Unpin window" : "Pin window")
            .help(isWindowPinned ? "Unpin window (⌘P)" : "Keep window open (⌘P)")
        }
    #endif
}
