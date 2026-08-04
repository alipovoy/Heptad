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

    // MARK: - isEmpty

    @Test func isEmptyTracksStoredData() throws {
        #expect(NoteItem(id: 0).isEmpty)

        let data = try #require(NoteItem.rtfData(from: NSAttributedString(string: "content")))
        #expect(NoteItem(id: 1, rtfData: data).isEmpty == false)
    }

    // MARK: - Timestamps

    /// The `modifiedAt` *parameter* defaults to `.now`, so a freshly created note is stamped
    /// with the time it was created. The stored *property* default of `.distantPast` is a
    /// separate thing — the lightweight-migration backfill for rows written before the
    /// property existed — and cannot be observed without a store.
    @Test func newNotesAreStampedWithTheCurrentTime() {
        let before = Date.now

        let note = NoteItem(id: 0)

        #expect(note.modifiedAt >= before)
        #expect(note.modifiedAt <= .now)
    }

    @Test func lastEditedAtReportsTheStampOfANoteWithContent() throws {
        let edited = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let data = try #require(NoteItem.rtfData(from: NSAttributedString(string: "content")))

        let note = NoteItem(id: 0, rtfData: data, modifiedAt: edited)

        #expect(note.lastEditedAt == edited)
    }

    /// An empty note carries the creation stamp all seven notes got at first launch. Reporting
    /// it would put an edit time the user never caused under a blank editor.
    @Test func lastEditedAtIsNilForAnEmptyNote() {
        #expect(NoteItem(id: 0).lastEditedAt == nil)
    }

    /// `.distantPast` is the lightweight-migration backfill for rows written before
    /// `modifiedAt` existed. Formatted, it reads "2,025 years ago".
    @Test func lastEditedAtIsNilForABackfilledStamp() throws {
        let data = try #require(NoteItem.rtfData(from: NSAttributedString(string: "content")))

        let note = NoteItem(id: 0, rtfData: data, modifiedAt: .distantPast)

        #expect(note.lastEditedAt == nil)
    }
}
