import SwiftUI

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

    /// Opens the snapshot list. The bar is where this app keeps its controls.
    let showSnapshots: () -> Void

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
                snapshotsButton
                #if os(macOS)
                    pinToggle
                #endif
            }

            HStack(spacing: 8) {
                countsText
                    .frame(maxWidth: .infinity, alignment: .leading)
                plainTextToggle
                snapshotsButton
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

    private var snapshotsButton: some View {
        Button(action: showSnapshots) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: AppConstants.Layout.pinToggleIconSize))
        }
        .buttonStyle(.plain)
        #if os(macOS)
            .focusable(false)
        #endif
        .accessibilityLabel("Snapshots")
        .help("Restore the notes from a snapshot")
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

/// Both halves of the bar's one branch — no edit to report, and a real edit time — both modes
/// of the plain-text toggle, and both halves of its fit: 320pt is the window minimum, where
/// the title drops out entirely.
#Preview("Statistics bar") {
    let populated = TextStats(text: "Lab credentials\nuser: admin\npass: rotate-me")

    return VStack(spacing: 12) {
        TextStatisticsBar(
            stats: .zero, title: NoteTitleCache.emptyTitle, lastEditedAt: nil,
            now: PreviewFixtures.now, color: .yellow, isPlainText: false, togglePlainText: {},
            showSnapshots: {}
        )
        .frame(width: 480)

        TextStatisticsBar(
            stats: populated, title: "Lab credentials",
            lastEditedAt: PreviewFixtures.now.addingTimeInterval(-300),
            now: PreviewFixtures.now, color: .red, isPlainText: true, togglePlainText: {},
            showSnapshots: {}
        )
        .frame(width: 480)

        TextStatisticsBar(
            stats: populated,
            title: "Release checklist for the long-title case, truncated in the bar",
            lastEditedAt: PreviewFixtures.now.addingTimeInterval(-86_400),
            now: PreviewFixtures.now, color: .green, isPlainText: false, togglePlainText: {},
            showSnapshots: {}
        )
        .frame(width: 480)

        TextStatisticsBar(
            stats: populated, title: "Lab credentials",
            lastEditedAt: PreviewFixtures.now.addingTimeInterval(-300),
            now: PreviewFixtures.now, color: .blue, isPlainText: true, togglePlainText: {},
            showSnapshots: {}
        )
        .frame(width: 320)
    }
    .padding()
}
