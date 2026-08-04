import Foundation
import Testing

@testable import Heptad

/// Covers the title the colour circles and the statistics bar show for a note: the rule that
/// derives it, and the cache that keeps it from decoding RTF on every render.
@MainActor
struct NoteTitleTests {

    // MARK: - Derivation

    /// Leading blank and whitespace-only lines are skipped: a note that opens with a blank
    /// line is still named after the first line that says something.
    @Test func deriveUsesTheFirstNonEmptyLine() {
        #expect(NoteTitleCache.derive(from: "\n   \nlab credentials\nsecond") == "lab credentials")
    }

    @Test func deriveTrimsSurroundingWhitespace() {
        #expect(NoteTitleCache.derive(from: "\t  padded  ") == "padded")
    }

    @Test(arguments: ["", "   ", "\n\n \n\t"])
    func deriveReportsEmptyForBlankText(text: String) {
        #expect(NoteTitleCache.derive(from: text) == NoteTitleCache.emptyTitle)
    }

    /// The 30-character cap, from both sides: a line at the limit is shown whole, and a longer
    /// one is cut to the limit plus an ellipsis.
    @Test func deriveShortensOnlyBeyondTheLimit() {
        let atLimit = String(repeating: "a", count: 30)
        #expect(NoteTitleCache.derive(from: atLimit) == atLimit)

        #expect(NoteTitleCache.derive(from: atLimit + "aaa") == atLimit + "…")
    }

    // MARK: - Caching

    @Test func titleDerivesFromTheNotesContent() throws {
        let note = NoteItem(id: 0, rtfData: try rtf("first line\nsecond"))

        #expect(NoteTitleCache().title(for: note) == "first line")
    }

    @Test func titleIsEmptyForANoteWithNoContent() {
        #expect(NoteTitleCache().title(for: NoteItem(id: 0)) == NoteTitleCache.emptyTitle)
    }

    /// The cache is keyed on the stored data, so an edit must not keep serving the old title.
    @Test func titleFollowsAnEditToTheNote() throws {
        let cache = NoteTitleCache()
        let note = NoteItem(id: 0, rtfData: try rtf("before"))
        #expect(cache.title(for: note) == "before")

        note.rtfData = try rtf("after")

        #expect(cache.title(for: note) == "after")
    }

    /// Entries are per note, not one shared slot — seven notes are cached side by side.
    @Test func titlesAreCachedPerNote() throws {
        let cache = NoteTitleCache()
        let first = NoteItem(id: 0, rtfData: try rtf("first"))
        let second = NoteItem(id: 1, rtfData: try rtf("second"))

        #expect(cache.title(for: first) == "first")
        #expect(cache.title(for: second) == "second")
        #expect(cache.title(for: first) == "first")
    }

    private func rtf(_ text: String) throws -> Data {
        try #require(NoteItem.rtfData(from: NSAttributedString(string: text)))
    }
}
