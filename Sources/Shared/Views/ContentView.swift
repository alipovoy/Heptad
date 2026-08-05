import SwiftData
import SwiftUI

/// Main root view for the application.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \NoteItem.id) private var notes: [NoteItem]
    @AppStorage(AppConstants.selectedNoteIndexKey) private var selectedNoteIndex = 0
    @State private var textStats: TextStats = .zero

    /// Ages the edit-time label in place. Started and stopped with the window below, so it
    /// never ticks against a window nobody can see.
    @State private var ticker = RelativeTimeTicker()

    /// Rotating local backups. Driven off the ticker below rather than a timer of its own:
    /// notes only change while the window is up, which is exactly when the ticker runs.
    @State private var snapshots = SnapshotStore()
    @State private var isShowingSnapshots = false

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
                        ColorPickerRow(selectedNoteIndex: $selectedNoteIndex, notes: notes)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)

                        IOSRichTextEditor(notes: notes, selectedNoteIndex: $selectedNoteIndex, textStats: $textStats)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    #endif

                    TextStatisticsBar(
                        stats: textStats,
                        title: NoteTitleCache.shared.title(for: notes[clampedNoteIndex]),
                        lastEditedAt: notes[clampedNoteIndex].lastEditedAt,
                        now: ticker.now,
                        color: NotePalette.colors[clampedNoteIndex],
                        isPlainText: notes[clampedNoteIndex].isPlainText,
                        togglePlainText: { notes[clampedNoteIndex].isPlainText.toggle() },
                        showSnapshots: { isShowingSnapshots = true }
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
        .onChange(of: ticker.now) { _, _ in
            // The store decides whether one is actually due; the ticker only asks.
            snapshots.writeIfDue(notes: notes)
        }
        .sheet(isPresented: $isShowingSnapshots) {
            SnapshotBrowser(snapshots: snapshots.snapshots(), restore: restore)
        }
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

        // Termination and backgrounding are the two moments worth a snapshot regardless of
        // when the last one was taken. The store still skips it when nothing has changed.
        snapshots.writeIfDue(notes: notes, force: true)
    }

    /// Puts every note back to `snapshot`.
    ///
    /// Order matters. Pending edits are flushed first, so a debounced save landing a moment
    /// later cannot overwrite what was just restored; the editors are told last, because they
    /// are showing text that has changed underneath them.
    private func restore(_ snapshot: NoteSnapshot) {
        NotificationCenter.default.post(name: .flushPendingSaves, object: nil)
        snapshots.restore(snapshot, into: notes)
        try? modelContext.save()
        NotificationCenter.default.post(name: .notesDidRestore, object: nil)
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
