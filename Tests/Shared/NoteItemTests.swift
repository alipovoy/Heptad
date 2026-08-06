import Foundation
import Testing

@testable import Heptad

/// Covers the RTF helpers on `NoteItem` — the single storage format every editor and the
/// saver go through. They were previously only exercised incidentally, through the tests
/// for their callers.
@MainActor
struct NoteItemTests {

    // MARK: - Decoding

    @Test func attributedContentIsNilForAnEmptyNote() {
        #expect(NoteItem(id: 0).attributedContent == nil)
    }

    /// Undecodable data must read as "no content" rather than trapping: the decode is a
    /// `try?`, and a note whose bytes were corrupted still has to open.
    @Test func attributedContentIsNilForUndecodableData() {
        let note = NoteItem(id: 0, rtfData: Data("garbage".utf8))

        #expect(note.attributedContent == nil)
    }

    @Test func attributedContentDecodesStoredText() throws {
        let data = try #require(NoteItem.rtfData(from: NSAttributedString(string: "stored")))
        let note = NoteItem(id: 0, rtfData: data)

        let decoded = try #require(note.attributedContent)

        #expect(decoded.string == "stored")
    }

    // MARK: - Encoding

    /// Content that is only whitespace encodes to empty data, which is what makes clearing
    /// a note wipe it instead of storing an RTF document full of spaces.
    @Test(arguments: ["", " ", "   \n  ", "\t\t", "\n"])
    func rtfDataIsEmptyForBlankContent(text: String) {
        #expect(NoteItem.rtfData(from: NSAttributedString(string: text)) == Data())
    }

    @Test func rtfDataRoundTripsRealContent() throws {
        let original = NSAttributedString(string: "Round trip me")

        let data = try #require(NoteItem.rtfData(from: original))
        #expect(data.isEmpty == false)

        let restored = try NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
        #expect(restored.string == original.string)
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
    func lastEditedAtReportsTheStampOrNilAtItsEdgeCases(testCase: LastEditedAtCase) throws {
        let data = try #require(NoteItem.rtfData(from: NSAttributedString(string: testCase.content)))
        let note = NoteItem(id: 0, rtfData: data, modifiedAt: testCase.stamp)

        #expect(note.lastEditedAt == testCase.expected)
    }
}
