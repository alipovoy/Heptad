import Foundation

/// A note's title: its first non-empty line, trimmed and shortened.
///
/// Cached because the callers are hot: the seven colour circles each want one, and the
/// statistics bar wants the selected note's. Deriving one from storage means decoding an RTF
/// document, so uncached that is seven decodes every time the notes change.
///
/// There are two ways in. `record(plainText:for:)` is the editor telling the cache what the
/// note now says, which is the common case and costs no decode at all. `title(for:)` falls
/// back to the stored data for notes nobody has opened yet, keyed on `rtfData` so an edit made
/// some other way cannot keep serving a stale title.
@MainActor
final class NoteTitleCache: NSObject {
    /// The instance the views share.
    static let shared = NoteTitleCache()

    /// Shown for a note with nothing in it.
    static let emptyTitle = "Empty"

    /// Cap on the derived title. Long enough for a recognisable first line, short enough to
    /// sit in the statistics bar beside the counts.
    private static let maxLength = 30

    /// A cached title, and the stored data it was derived from — nil when it came from the
    /// editor instead, which is text the note has not been written back to yet.
    private struct Entry {
        let rtfData: Data?
        let title: String
    }

    private var entries: [Int: Entry] = [:]

    override init() {
        super.init()

        // A restore rewrites `rtfData` from outside the editors, so nothing records the new
        // text and an editor-sourced entry would go on describing the text that was replaced.
        // It is the one writer that is neither the saver nor a keystroke.
        //
        // No removeObserver needed: selector-based observers auto-unregister on deinit.
        NotificationCenter.default.addObserver(
            self, selector: #selector(discardEntries), name: .notesDidRestore, object: nil)
    }

    /// The title of `note`, from the editor's own text when it has been recorded.
    func title(for note: NoteItem) -> String {
        if let entry = entries[note.id], entry.rtfData == nil || entry.rtfData == note.rtfData {
            return entry.title
        }

        let title = Self.derive(from: note.plainTextContent)
        entries[note.id] = Entry(rtfData: note.rtfData, title: title)
        return title
    }

    /// Takes the note's title straight from the text on screen.
    ///
    /// Called on every keystroke, which is the point: the saver rewrites `rtfData` a few times
    /// a second, and each rewrite would otherwise be a cache miss and so a full RTF document
    /// parse, on the main actor, to read a first line the editor already had in hand.
    func record(plainText: String, for noteId: Int) {
        entries[noteId] = Entry(rtfData: nil, title: Self.derive(from: plainText))
    }

    /// `@objc` selector dispatch does not hop actors, so this cannot be isolated directly.
    /// The only poster is `ContentView`, on the main actor.
    @objc nonisolated private func discardEntries() {
        MainActor.assumeIsolated { entries.removeAll() }
    }

    /// The whole of the rule the cache memoises, kept pure so it can be tested on its own.
    ///
    /// Scans to the end of the first non-empty line rather than splitting the note into lines:
    /// `record` runs per keystroke, and all but the first line of the answer is thrown away.
    static func derive(from text: String) -> String {
        var lineStart = text.startIndex

        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(where: \.isNewline) ?? text.endIndex
            let trimmed = text[lineStart..<lineEnd].trimmingCharacters(in: .whitespaces)

            if !trimmed.isEmpty {
                guard trimmed.count > maxLength else { return trimmed }
                return String(trimmed.prefix(maxLength)).trimmingCharacters(in: .whitespaces) + "…"
            }

            guard lineEnd < text.endIndex else { break }
            lineStart = text.index(after: lineEnd)
        }

        return emptyTitle
    }
}
