import SwiftUI

struct TextStatisticsBar: View {
    /// Read here rather than passed in as plain `TextStats`, so that a keystroke invalidates
    /// this bar alone instead of `ContentView` and everything under it.
    let statistics: EditorStatistics

    /// When the selected note was last edited, or nil for a note with no edit to report.
    let lastEditedAt: Date?

    /// The clock the edit time is measured against, handed over as the ticker rather than as a
    /// `Date`: reading `now` is what subscribes a view to the tick, and reading it in
    /// `ContentView`'s body re-evaluated the whole tree every 30 seconds.
    let ticker: RelativeTimeTicker

    let color: Color

    /// The selected note's editing mode, and the way to flip it. Both live on the note, so
    /// the bar only reports and asks — `ContentView` owns the write.
    let isPlainText: Bool
    let togglePlainText: () -> Void

    #if os(macOS)
        /// The live window state `WindowManager` owns, so the pin button always shows the truth —
        /// including when the state changes by ⌘P, by dragging the panel away, or by the window
        /// hiding, which reattaches it.
        @Environment(WindowState.self) private var windowState

        /// Fixed: the panel is a menubar popover and accessibility text sizes would break the
        /// layout it is built around.
        private let statisticsFontSize = Self.baseStatisticsFontSize
        private let toggleIconSize = Self.baseToggleIconSize
    #else
        /// Scaled: iOS is a full-screen window whose text size the user sets. The same numbers,
        /// so nothing moves at the default.
        @ScaledMetric(relativeTo: .caption2) private var statisticsFontSize =
            Self.baseStatisticsFontSize
        @ScaledMetric(relativeTo: .body) private var toggleIconSize = Self.baseToggleIconSize
    #endif

    /// The sizes the two `#if` branches above start from: drawn as they stand on macOS, scaled
    /// with Dynamic Type on iOS.
    private static let baseStatisticsFontSize: CGFloat = 11
    private static let baseToggleIconSize: CGFloat = 13

    var body: some View {
        // What the note is on the left, what you can do to it on the right. The counts take
        // the leftover width and truncate into it, so the buttons keep the same place at every
        // window size instead of being shunted about by the length of the text beside them.
        //
        // The 8 is the gap between the counts and the buttons, unrelated to the padding below
        // despite matching it.
        HStack(spacing: 8) {
            countsText
                .frame(maxWidth: .infinity, alignment: .leading)
            plainTextToggle
            #if os(macOS)
                pinToggle
            #endif
        }
        .font(.system(size: statisticsFontSize, weight: .medium, design: .rounded))
        .padding(.vertical, AppConstants.Layout.rowInset)
        .padding(.horizontal, AppConstants.Layout.edgeInset)
        .background(color.opacity(Self.tintOpacity))
        .foregroundStyle(.secondary)  // Vivid text color relying on the background
    }

    /// Twice the window's own wash, so the bar reads as a band across the bottom rather than as
    /// more of the note. Not derived from `Layout.noteTintOpacity`: that is the paper, this is the
    /// band on it.
    private static let tintOpacity: Double = 0.2

    /// The per-note plain-text switch. It sits here rather than in the macOS title bar the
    /// issue suggested: the two icons are different widths, and anything of variable width up
    /// there pushes the colour circles off centre — the same reason the pin toggle is here.
    private var plainTextToggle: some View {
        Button(action: togglePlainText) {
            Image(systemName: isPlainText ? "curlybraces" : "textformat")
                .font(.system(size: toggleIconSize))
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
        return " ⋅ "
            + RelativeEditTimeFormatter.shared.string(for: lastEditedAt, relativeTo: ticker.now)
    }

    #if os(macOS)
        /// Sized against the 11pt statistics text it sits beside, and left to inherit the bar's
        /// secondary foreground style in both states — outlined vs filled carries the meaning.
        private var pinToggle: some View {
            Button {
                // WindowManager owns and persists the state; this only asks it to flip.
                NotificationCenter.default.post(name: .toggleWindowPin, object: nil)
            } label: {
                Image(systemName: windowState.isPinned ? "pin.fill" : "pin.slash")
                    .font(.system(size: toggleIconSize))
            }
            .buttonStyle(.plain)
            .focusable(false)
            .accessibilityLabel(windowState.isPinned ? "Unpin window" : "Pin window")
            .help(windowState.isPinned ? "Unpin window (⌘P)" : "Keep window open (⌘P)")
        }
    #endif
}

/// Both sides of the bar's one branch — no edit to report, and a real edit time — both modes of
/// the plain-text toggle, and `AppConstants.Window.minimumContentSize.width`, where the counts
/// truncate and the buttons stay where they are.
#Preview("Statistics bar") {
    let populated = TextStats(text: "Lab credentials\nuser: admin\npass: rotate-me")

    return VStack(spacing: 12) {
        TextStatisticsBar(
            statistics: EditorStatistics(), lastEditedAt: nil,
            ticker: PreviewFixtures.ticker(), color: .yellow, isPlainText: false,
            togglePlainText: {}
        )
        .frame(width: 480)

        TextStatisticsBar(
            statistics: EditorStatistics(stats: populated),
            lastEditedAt: PreviewFixtures.now.addingTimeInterval(-300),
            ticker: PreviewFixtures.ticker(), color: .red, isPlainText: true, togglePlainText: {}
        )
        .frame(width: 480)

        TextStatisticsBar(
            statistics: EditorStatistics(stats: populated),
            lastEditedAt: PreviewFixtures.now.addingTimeInterval(-86_400),
            ticker: PreviewFixtures.ticker(), color: .blue, isPlainText: true, togglePlainText: {}
        )
        .frame(width: AppConstants.Window.minimumContentSize.width)
    }
    .padding()
    #if os(macOS)
        // The pin toggle reads this out of the environment, so a preview without it would trap
        // rather than draw.
        .environment(WindowState())
    #endif
}
