import SwiftData
import SwiftUI

/// Main root view for the application.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \NoteItem.id) private var notes: [NoteItem]
    @AppStorage(AppConstants.selectedNoteIndexKey) private var selectedNoteIndex = 0
    /// Deliberately not read in this body: the editors write to it and `TextStatisticsBar`
    /// reads it, so a keystroke invalidates the bar and nothing else. Held here as plain
    /// `TextStats` it re-evaluated this whole view — title bar, seven colour circles,
    /// background and the representable — for every character typed.
    @State private var statistics = EditorStatistics()

    /// Ages the edit-time label in place. Started and stopped with the window below, so it
    /// never ticks against a window nobody can see.
    @State private var ticker = RelativeTimeTicker()

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

                        MacRichTextEditor(notes: notes, selectedNoteIndex: $selectedNoteIndex, statistics: statistics)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(backgroundFill)
                    #else
                        ColorPickerRow(selectedNoteIndex: $selectedNoteIndex, notes: notes)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)

                        IOSRichTextEditor(notes: notes, selectedNoteIndex: $selectedNoteIndex, statistics: statistics)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    #endif

                    TextStatisticsBar(
                        statistics: statistics,
                        lastEditedAt: notes[clampedNoteIndex].lastEditedAt,
                        now: ticker.now,
                        color: NotePalette.colors[clampedNoteIndex],
                        isPlainText: notes[clampedNoteIndex].isPlainText,
                        togglePlainText: { notes[clampedNoteIndex].isPlainText.toggle() }
                    )
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
        .onAppear {
            ticker.start()

            // Writes the clamp back, so every reader of the selection agrees on it. The editors
            // and the colour circles take the stored value as a binding rather than through
            // `clampedNoteIndex`, and left at a junk index `NoteEditorCoordinator.update` would
            // decline to install any editor view at all: a blank, untypable note beside a
            // statistics bar describing a different one. Reading it clamped above keeps the
            // first frame — which renders before this runs — from indexing out of bounds.
            if selectedNoteIndex != clampedNoteIndex {
                selectedNoteIndex = clampedNoteIndex
            }
        }
        .onDisappear { ticker.stop() }
        // iOS backgrounding. Inert on macOS: ContentView is mounted in a bare NSHostingView with
        // no Scene behind it, so scenePhase never changes there — WindowManager posts
        // `.flushPendingSaves` itself when it hides the window, and the notifications below
        // stand in for the visibility changes this never reports.
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background || newPhase == .inactive {
                flushPendingSaves()
                ticker.stop()
            } else {
                ticker.start()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Self.willTerminateNotification)) { _ in
            flushPendingSaves()
        }
        #if os(macOS)
            // The window is ordered out, not unmounted, so `onDisappear` above never fires for it.
            .onReceive(NotificationCenter.default.publisher(for: .windowDidBecomeVisible)) { _ in
                ticker.start()
            }
            .onReceive(NotificationCenter.default.publisher(for: .windowDidHide)) { _ in
                ticker.stop()
            }
        #endif
    }

    /// Asks every `NoteContentSaver` to write its pending text, then commits the context.
    ///
    /// `NotificationCenter.post` is synchronous, so all the model writes have landed by the time
    /// `save()` runs. Without it durability rests on `autosaveEnabled`, whose trigger points are
    /// undocumented — at terminate that is a race against process exit.
    private func flushPendingSaves() {
        NotificationCenter.default.post(name: .flushPendingSaves, object: nil)
        try? modelContext.save()
    }

    /// `selectedNoteIndex` brought inside the bounds of `NotePalette.colors` and of `notes`.
    ///
    /// The stored value is plain `UserDefaults` — writable from outside the app, and carried
    /// across versions that may not have had seven notes — and nothing sanity-checks it on read.
    /// Indexing either array with it raw turns a junk default into a crash at launch, in a
    /// menubar app with no window and no Dock icon: clicking the icon would simply do nothing,
    /// with no visible explanation. `NoteEditorCoordinator.update` already guards its own
    /// indexing; this is the same defensiveness on the views that read the selection directly.
    ///
    /// Bounded by the shorter of the two arrays it indexes: the palette, and `notes`, whose
    /// count this is only ever read after checking against `AppConstants.noteCount`.
    private var clampedNoteIndex: Int {
        min(max(selectedNoteIndex, 0), min(NotePalette.colors.count, AppConstants.noteCount) - 1)
    }

    private var backgroundFill: some View {
        NotePalette.colors[clampedNoteIndex].opacity(0.1)
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

                ColorPickerRow(selectedNoteIndex: $selectedNoteIndex, notes: notes)

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

#Preview("Seeded") {
    ContentView()
        .modelContainer(PreviewFixtures.container())
        .frame(width: 420, height: 320)
}

/// The branch that shows until the seven notes exist — an empty store stands in for the
/// moment before `HeptadApp` has seeded one.
#Preview("Initializing") {
    ContentView()
        .modelContainer(PreviewFixtures.container(seeded: false))
        .frame(width: 420, height: 320)
}
