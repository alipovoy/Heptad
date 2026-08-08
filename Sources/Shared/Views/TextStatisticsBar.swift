import SwiftUI

struct TextStatisticsBar: View {
    /// Read here rather than passed in as plain `TextStats`, so that a keystroke invalidates
    /// this bar alone instead of `ContentView` and everything under it.
    let statistics: EditorStatistics

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
        // What the note is on the left, what you can do to it on the right. The counts take
        // the leftover width and truncate into it, so the buttons keep the same place at every
        // window size instead of being shunted about by the length of the text beside them.
        HStack(spacing: 8) {
            countsText
                .frame(maxWidth: .infinity, alignment: .leading)
            plainTextToggle
            #if os(macOS)
                pinToggle
            #endif
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
        // Named for what the toggle does to the note's Markdown, since that is the visible
        // difference: one mode draws it, the other leaves it as the characters you typed.
        .accessibilityLabel(isPlainText ? "Show Markdown formatting" : "Show Markdown as plain text")
        .help(
            isPlainText
                ? "Formatted Markdown for this note"
                : "Plain monospaced Markdown source for this note")
    }

    /// One `Text` so the counts read as a single run and wrap and truncate together.
    private var countsText: some View {
        let stats = statistics.stats
        return Text(
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

/// Both sides of the bar's one branch — no edit to report, and a real edit time — both modes of
/// the plain-text toggle, and the 320pt window minimum, where the counts truncate and the
/// buttons stay where they are.
#Preview("Statistics bar") {
    let populated = TextStats(text: "Lab credentials\nuser: admin\npass: rotate-me")

    return VStack(spacing: 12) {
        TextStatisticsBar(
            statistics: EditorStatistics(), lastEditedAt: nil,
            now: PreviewFixtures.now, color: .yellow, isPlainText: false, togglePlainText: {}
        )
        .frame(width: 480)

        TextStatisticsBar(
            statistics: EditorStatistics(stats: populated),
            lastEditedAt: PreviewFixtures.now.addingTimeInterval(-300),
            now: PreviewFixtures.now, color: .red, isPlainText: true, togglePlainText: {}
        )
        .frame(width: 480)

        TextStatisticsBar(
            statistics: EditorStatistics(stats: populated),
            lastEditedAt: PreviewFixtures.now.addingTimeInterval(-86_400),
            now: PreviewFixtures.now, color: .blue, isPlainText: true, togglePlainText: {}
        )
        .frame(width: 320)
    }
    .padding()
}
