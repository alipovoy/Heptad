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

                    TextStatisticsBar(
                        stats: textStats,
                        title: NoteTitleCache.shared.title(for: notes[clampedNoteIndex]),
                        lastEditedAt: notes[clampedNoteIndex].lastEditedAt,
                        now: ticker.now,
                        color: Self.colors[clampedNoteIndex],
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

    /// `selectedNoteIndex` brought inside the bounds of `colors` and of `notes`.
    ///
    /// The stored value is plain `UserDefaults` — writable from outside the app, and carried
    /// across versions that may not have had seven notes — and nothing sanity-checks it on read.
    /// Indexing either array with it raw turns a junk default into a crash at launch, in a
    /// menubar app with no window and no Dock icon: clicking the icon would simply do nothing,
    /// with no visible explanation. `NoteEditorCoordinator.update` already guards its own
    /// indexing; this is the same defensiveness on the views that read the selection directly.
    ///
    /// Bounded by the shorter of the two arrays it indexes: `colors`, and `notes`, whose count
    /// this is only ever read after checking against `AppConstants.noteCount`.
    private var clampedNoteIndex: Int {
        min(max(selectedNoteIndex, 0), min(Self.colors.count, AppConstants.noteCount) - 1)
    }

    private var backgroundFill: some View {
        Self.colors[clampedNoteIndex].opacity(0.1)
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

    /// The selected note's first line, named here rather than only on hover over its circle.
    let title: String

    /// When the selected note was last edited, or nil for a note with no edit to report.
    let lastEditedAt: Date?

    /// What the edit time is measured against. Passed in rather than read here so the bar
    /// re-renders when `RelativeTimeTicker` moves it on, and so tests can pin it.
    let now: Date

    let color: Color

    /// The selected note's editing mode, and the way to flip it. Both live on the note, so
    /// the bar only reports and asks — `ContentView` owns the write.
    let isPlainText: Bool
    let togglePlainText: () -> Void

    #if os(macOS)
        /// Read-only mirror of the window state WindowManager persists, so the pin button always
        /// shows the truth — including when the state changes by ⌘P or by dragging the panel away.
        @AppStorage(AppConstants.windowPinnedKey) private var isWindowPinned = false
    #endif

    var body: some View {
        // Both when they fit, the counts alone when they do not. Squeezing the two against
        // each other instead leaves the loser as a one-glyph stub at the window's 320pt
        // minimum; dropping the title whole is tidier, and it is still on every colour circle.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                titleText
                Spacer(minLength: 8)
                countsText
                plainTextToggle
                #if os(macOS)
                    pinToggle
                #endif
            }

            HStack(spacing: 8) {
                countsText
                    .frame(maxWidth: .infinity, alignment: .leading)
                plainTextToggle
                #if os(macOS)
                    pinToggle
                #endif
            }
        }
        .font(
            .system(
                size: AppConstants.Layout.statisticsFontSize, weight: .medium, design: .rounded))
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(color.opacity(0.2))
        .foregroundStyle(.secondary)  // Vivid text color relying on the background
    }

    /// The per-note plain-text switch. It sits here rather than in the macOS title bar the
    /// issue suggested: the two icons are different widths, and anything of variable width up
    /// there pushes the colour circles off centre — the same reason the pin toggle is here.
    private var plainTextToggle: some View {
        Button(action: togglePlainText) {
            Image(systemName: isPlainText ? "curlybraces" : "textformat")
                .font(.system(size: AppConstants.Layout.pinToggleIconSize))
        }
        .buttonStyle(.plain)
        #if os(macOS)
            .focusable(false)
        #endif
        .accessibilityLabel(isPlainText ? "Use rich text" : "Use plain text")
        .help(isPlainText ? "Rich text for this note" : "Plain monospaced text for this note")
    }

    /// Capped so a long first line does not make the whole two-part layout look unfittable
    /// and drop itself; past the cap it truncates, which is what the tooltip is for.
    private var titleText: some View {
        Text(title)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: 160, alignment: .leading)
            .help(title)  // The untruncated first line
    }

    /// One `Text` so the counts read as a single run and wrap and truncate together.
    private var countsText: some View {
        Text(
            """
            \(stats.lines) Lines ⋅ \(stats.words) Words ⋅ \(stats.characters) \
            Characters\(editedSuffix)
            """
        )
        .lineLimit(1)
        .truncationMode(.tail)
        #if os(macOS)
            // The exact time, for when "yesterday" is not precise enough. Empty when there
            // is no edit to report, which AppKit reads as "no tooltip".
            .help(lastEditedAt?.formatted(date: .abbreviated, time: .shortened) ?? "")
        #endif
    }

    /// The relative edit time as one more entry in the statistics run — " ⋅ 5 minutes ago" —
    /// or empty for a note with no edit to report.
    ///
    /// Part of the same `Text` rather than a view of its own so it wraps and truncates as one
    /// sentence with the counts, and so the separator matches the ones between them.
    private var editedSuffix: String {
        guard let lastEditedAt else { return "" }
        return " ⋅ " + RelativeEditTimeFormatter.shared.string(for: lastEditedAt, relativeTo: now)
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

/// Both halves of the bar's one branch — no edit to report, and a real edit time — both modes
/// of the plain-text toggle, and both halves of its fit: 320pt is the window minimum, where
/// the title drops out entirely.
#Preview("Statistics bar") {
    let populated = TextStats(text: "Lab credentials\nuser: admin\npass: rotate-me")

    return VStack(spacing: 12) {
        TextStatisticsBar(
            stats: .zero, title: NoteTitleCache.emptyTitle, lastEditedAt: nil,
            now: PreviewFixtures.now, color: .yellow, isPlainText: false, togglePlainText: {}
        )
        .frame(width: 480)

        TextStatisticsBar(
            stats: populated, title: "Lab credentials",
            lastEditedAt: PreviewFixtures.now.addingTimeInterval(-300),
            now: PreviewFixtures.now, color: .red, isPlainText: true, togglePlainText: {}
        )
        .frame(width: 480)

        TextStatisticsBar(
            stats: populated,
            title: "Release checklist for the long-title case, truncated in the bar",
            lastEditedAt: PreviewFixtures.now.addingTimeInterval(-86_400),
            now: PreviewFixtures.now, color: .green, isPlainText: false, togglePlainText: {}
        )
        .frame(width: 480)

        TextStatisticsBar(
            stats: populated, title: "Lab credentials",
            lastEditedAt: PreviewFixtures.now.addingTimeInterval(-300),
            now: PreviewFixtures.now, color: .blue, isPlainText: true, togglePlainText: {}
        )
        .frame(width: 320)
    }
    .padding()
}
