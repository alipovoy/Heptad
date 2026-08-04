import Foundation

/// A note's title: its first non-empty line, trimmed and shortened.
///
/// Cached because the callers are hot. `ContentView` re-renders on every keystroke — the
/// statistics binding changes — and it draws seven colour circles, each wanting a title.
/// Deriving one means decoding an RTF document, so uncached that is seven decodes per typed
/// character. `rtfData` is the cache key: it is the only input, and comparing it is a memcmp
/// against a decode. Seven notes means seven entries, so nothing needs evicting.
@MainActor
final class NoteTitleCache {
    /// The instance the views share.
    static let shared = NoteTitleCache()

    /// Shown for a note with nothing in it.
    static let emptyTitle = "Empty"

    /// Cap on the derived title. Long enough for a recognisable first line, short enough to
    /// sit in the statistics bar beside the counts.
    private static let maxLength = 30

    private var entries: [Int: (rtfData: Data, title: String)] = [:]

    func title(for note: NoteItem) -> String {
        if let entry = entries[note.id], entry.rtfData == note.rtfData { return entry.title }

        let title = Self.derive(from: note.attributedContent?.string ?? "")
        entries[note.id] = (note.rtfData, title)
        return title
    }

    /// The whole of the rule the cache memoises, kept pure so it can be tested on its own.
    static func derive(from text: String) -> String {
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard trimmed.count > maxLength else { return trimmed }
            return String(trimmed.prefix(maxLength)).trimmingCharacters(in: .whitespaces) + "…"
        }
        return emptyTitle
    }
}
