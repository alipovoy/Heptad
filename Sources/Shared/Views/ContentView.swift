import SwiftData
import SwiftUI

/// Main root view for the application.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    /// Everything the store holds, in id order. Read through `notes` below, never directly.
    @Query(sort: \NoteItem.id) private var stored: [NoteItem]
    /// The raw stored selection. Read through `selectedNoteIndex` and written through
    /// `selection`, both below — never indexed with directly. See `NoteSelection`.
    @AppStorage(AppConstants.selectedNoteIndexKey) private var storedNoteIndex = 0
    /// Deliberately not read in this body: the editors write to it and `TextStatisticsBar`
    /// reads it, so a keystroke invalidates the bar and nothing else. Held here as plain
    /// `TextStats` it re-evaluated this whole view — title bar, seven colour circles,
    /// background and the representable — for every character typed.
    @State private var statistics = EditorStatistics()

    /// Ages the edit-time label in place. Started and stopped with the window below, so it
    /// never ticks against a window nobody can see.
    @State private var ticker = RelativeTimeTicker()

    /// The seven notes this view addresses, by id rather than by how many rows there are.
    ///
    /// Everything above `NoteEditorCoordinator` addresses a note by its position in this array,
    /// so what it has to hold is ids `0..<noteCount` in order — which counting rows is only a
    /// proxy for. A store holding an eighth id has seven perfectly good notes in it, and the
    /// count made that a permanent "could not be loaded" with all seven intact on disk and
    /// unreachable. Extras are ignored rather than deleted: they are not this view's to remove.
    private var notes: [NoteItem] { stored.filter { $0.id < AppConstants.noteCount } }

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

                        MacRichTextEditor(notes: notes, selectedNoteIndex: selection, statistics: statistics)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(backgroundFill)
                    #else
                        ColorPickerRow(selectedNoteIndex: selection, notes: notes)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)

                        IOSRichTextEditor(notes: notes, selectedNoteIndex: selection, statistics: statistics)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    #endif

                    statisticsBar(for: selectedNote)
                    #if os(macOS)
                        // macOS alone: there is no root background there, so each part of the
                        // stack paints its own. iOS has one below, and painting the bar again
                        // composited a second 0.1 of the note's colour under it — a tint 26%
                        // stronger than the same bar on macOS.
                        .background(backgroundFill)
                    #endif
                }
                #if !os(macOS)
                    .background(backgroundFill.ignoresSafeArea(edges: [.bottom, .leading, .trailing]))
                #endif
            } else {
                // Not a state anything is working its way out of. `sharedModelContainer` seeds
                // before it hands the container over, and both mount sites take it from there, so
                // the first pass never runs against an unseeded store — and nothing afterwards
                // adds or removes a note. Taken once, this branch is taken forever, and the
                // spinner that used to be here promised progress that was not happening.
                ContentUnavailableView(
                    "Notes could not be loaded",
                    systemImage: "exclamationmark.triangle",
                    description: Text(
                        "Expected \(AppConstants.noteCount) notes, found \(notes.count). "
                            + "Quit and remove the note store to start over."))
            }
        }
        #if os(macOS)
            // On the `Group`, so the unavailable branch is sized and inset like the editor is:
            // the panel draws no title bar, and without these the message sat under one that is
            // not there, in a window the user could shrink to nothing.
            .frame(
                minWidth: AppConstants.Window.minimumContentSize.width,
                minHeight: AppConstants.Window.minimumContentSize.height)
            .ignoresSafeArea(.all, edges: .top)
        #endif
        .onAppear { ticker.start() }
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
                // `WindowManager.hide` has already asked the savers to flush — this is the half it
                // cannot do, having no model context. The second post is inert (nothing is pending
                // by now) and keeps one name for "make the notes durable". Without it, a dismissal
                // was durable only because SwiftData's autosave happens to fire on the
                // deactivation that follows.
                flushPendingSaves()
                ticker.stop()
            }
        #endif
    }

    /// The bar, built against the note itself rather than against `selectedNote`.
    ///
    /// `togglePlainText` escapes: `TextStatisticsBar` stores it and a `Button` calls it later, at
    /// which point reading `selectedNote` would mean reading `@Query` and `@AppStorage` off a
    /// captured copy of this view, outside the `body` pass that made it — the hazard `selection`
    /// below is built the way it is to avoid. A `NoteItem` is a reference, so capturing one is
    /// capturing the note and nothing else.
    private func statisticsBar(for note: NoteItem) -> some View {
        TextStatisticsBar(
            statistics: statistics,
            lastEditedAt: note.lastEditedAt,
            ticker: ticker,
            color: NotePalette.colors[selectedNoteIndex],
            isPlainText: note.isPlainText,
            togglePlainText: { note.isPlainText.toggle() }
        )
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

    /// The selection, brought inside the bounds of `notes` — see `NoteSelection`. Only read
    /// where the count check above has passed, so it always names a note that exists.
    private var selectedNoteIndex: Int {
        NoteSelection.clamped(storedNoteIndex, noteCount: notes.count)
    }

    /// What the colour circles and the editors bind to: clamped on the way out, stored as given
    /// on the way in. Handing them this rather than `$storedNoteIndex` is what keeps a junk
    /// stored value from reaching `NoteEditorCoordinator`, which indexes `notes` with it.
    ///
    /// Built from the projected binding and the count rather than by reading the properties
    /// inside the closures: a `Binding` outlives the `body` pass that made it — the circles
    /// write through it from a tap — and closures that read them would capture a copy of the
    /// view whose dynamic properties are only guaranteed live during that pass.
    /// `$storedNoteIndex` addresses the store itself, so reading it later is still correct.
    private var selection: Binding<Int> {
        let stored = $storedNoteIndex
        let noteCount = notes.count
        return Binding(
            get: { NoteSelection.clamped(stored.wrappedValue, noteCount: noteCount) },
            set: { stored.wrappedValue = $0 })
    }

    private var selectedNote: NoteItem { notes[selectedNoteIndex] }

    /// The note's colour, faintly. Plain, with no `ignoresSafeArea` folded in: only the root fill
    /// on iOS has a safe area to ignore, and carrying it on the shared value applied it to two
    /// more uses that sit in the middle of a `VStack`.
    private var backgroundFill: some View {
        NotePalette.colors[selectedNoteIndex].opacity(0.1)
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

                ColorPickerRow(selectedNoteIndex: selection, notes: notes)

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
        #if os(macOS)
            .environment(WindowState())
        #endif
}

/// The branch that shows when the store does not hold the seven notes — an empty store stands in
/// for a seed that did not happen. Not a loading state: nothing later fills it in.
#Preview("Notes missing") {
    ContentView()
        .modelContainer(PreviewFixtures.container(seeded: false))
        .frame(width: 420, height: 320)
        #if os(macOS)
            .environment(WindowState())
        #endif
}
