import Foundation
import Testing

@testable import Heptad

/// Covers the storage helpers on `NoteItem`. A note is markdown source now, so these are about
/// which text counts as "nothing written here" rather than about encoding.
@MainActor
struct NoteItemTests {

    // MARK: - Stored text

    /// Content that is only whitespace stores as the empty string, which is what makes clearing
    /// a note wipe it instead of leaving a stray newline behind for `⌘0` to trip over.
    @Test(arguments: ["", " ", "   \n  ", "\t\t", "\n"])
    func storedTextIsEmptyForBlankContent(text: String) {
        #expect(NoteItem.storedText(from: text) == "")
    }

    /// Markdown is stored verbatim: the delimiters are the note's content, not decoration
    /// applied to it, so nothing here may rewrite them.
    @Test func storedTextKeepsRealContentExactly() {
        let text = "**bold** and _italic_ and ~~struck~~\n- [x] done\n  trailing space kept  "
        #expect(NoteItem.storedText(from: text) == text)
    }

    // MARK: - Timestamps

    /// One case of the `lastEditedAt` contract: the content and stamp a note is built with, and
    /// what `lastEditedAt` ought to report for it.
    struct LastEditedAtCase: Sendable, CustomTestStringConvertible {
        let content: String
        let stamp: Date
        let expected: Date?

        var testDescription: String { "\(String(reflecting: content)) @ \(stamp) → \(String(describing: expected))" }
    }

    /// `lastEditedAt` reports `modifiedAt` for a note with content, and nil at its two edge
    /// cases: an empty note (there is nothing to date — reporting one would put an edit time
    /// the user never caused under a blank editor) and a `.distantPast` stamp (the
    /// lightweight-migration backfill for rows written before `modifiedAt` existed, which
    /// formatted would read "2,025 years ago").
    @Test(arguments: [
        LastEditedAtCase(
            content: "content", stamp: Date(timeIntervalSinceReferenceDate: 800_000_000),
            expected: Date(timeIntervalSinceReferenceDate: 800_000_000)),
        LastEditedAtCase(
            content: "", stamp: Date(timeIntervalSinceReferenceDate: 800_000_000), expected: nil),
        LastEditedAtCase(content: "content", stamp: .distantPast, expected: nil)
    ])
    func lastEditedAtReportsTheStampOrNilAtItsEdgeCases(testCase: LastEditedAtCase) {
        let note = NoteItem(
            id: 0, text: NoteItem.storedText(from: testCase.content), modifiedAt: testCase.stamp)

        #expect(note.lastEditedAt == testCase.expected)
    }
}
