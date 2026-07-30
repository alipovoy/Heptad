import XCTest

@testable import Heptad

@MainActor
final class NoteContentSaverTests: XCTestCase {

    func testSerializationAndDebouncing() async throws {
        // Arrange
        let note = NoteItem(id: 0)
        let center = NotificationCenter()
        let saver = NoteContentSaver(note: note, debounce: .milliseconds(100), notificationCenter: center)

        let attrString = NSAttributedString(string: "Hello Test")

        // Act
        saver.save(attributedString: attrString)

        // Poll to a deadline rather than sleeping a fixed interval past the debounce — see
        // `waitUntil`. Reaching the next line already proves the save landed.
        try await waitUntil("the debounced save to write RTF") { !note.rtfData.isEmpty }

        // Assert
        let data = note.rtfData
        let restored = try NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
        XCTAssertEqual(restored.string, "Hello Test")  // RTF doesn't add a trailing newline here
    }

    func testDebounceCancelsPrevious() async throws {
        let note = NoteItem(id: 0)
        let center = NotificationCenter()
        let saver = NoteContentSaver(note: note, debounce: .milliseconds(150), notificationCenter: center)

        let str1 = NSAttributedString(string: "A")
        let str2 = NSAttributedString(string: "AB")
        let str3 = NSAttributedString(string: "ABC")

        saver.save(attributedString: str1)
        saver.save(attributedString: str2)
        saver.save(attributedString: str3)

        // Only the last `save` survives — the earlier two are cancelled before they write —
        // so a single non-empty `rtfData` is the whole observable outcome.
        try await waitUntil("the debounced save to write RTF") { !note.rtfData.isEmpty }

        let data = note.rtfData
        let restored = try NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
        XCTAssertEqual(restored.string, "ABC")  // RTF doesn't add trailing newline here
    }

    func testEmptyStringOutputsEmptyData() async throws {
        let note = NoteItem(id: 0)
        let center = NotificationCenter()
        let saver = NoteContentSaver(note: note, debounce: .milliseconds(50), notificationCenter: center)

        // Provide empty string
        saver.save(attributedString: NSAttributedString(string: ""))
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertTrue(note.rtfData.isEmpty)

        // Provide spaces
        saver.save(attributedString: NSAttributedString(string: "   \n  "))
        XCTAssertTrue(note.rtfData.isEmpty)
    }

    func testSaveUpdatesModifiedAt() async throws {
        let note = NoteItem(id: 0, modifiedAt: .distantPast)
        let center = NotificationCenter()
        let saver = NoteContentSaver(note: note, debounce: .milliseconds(50), notificationCenter: center)

        let before = Date.now
        saver.save(attributedString: NSAttributedString(string: "Edited"))
        try await waitUntil("the debounced save to write RTF") { !note.rtfData.isEmpty }

        XCTAssertGreaterThanOrEqual(note.modifiedAt, before)
        XCTAssertLessThanOrEqual(note.modifiedAt, .now)
    }

    func testUnchangedContentLeavesModifiedAtAlone() async throws {
        let note = NoteItem(id: 0)
        let center = NotificationCenter()
        let saver = NoteContentSaver(note: note, debounce: .milliseconds(50), notificationCenter: center)

        saver.save(attributedString: NSAttributedString(string: "Same"))
        try await waitUntil("the debounced save to write RTF") { !note.rtfData.isEmpty }
        let firstEdit = note.modifiedAt

        // Re-saving identical content — what reopening or switching back to a note does —
        // short-circuits on the unchanged-data guard, so the timestamp must not move.
        saver.save(attributedString: NSAttributedString(string: "Same"))
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(note.modifiedAt, firstEdit)
    }

    func testFlushImmediatelySavesPending() throws {
        let note = NoteItem(id: 0)
        let center = NotificationCenter()
        let saver = NoteContentSaver(note: note, debounce: .seconds(5), notificationCenter: center)

        let str = NSAttributedString(string: "Flushed Text")
        saver.save(attributedString: str)

        // The save is debounced so the note should not have it yet
        XCTAssertTrue(note.rtfData.isEmpty)

        // Simulate notification
        center.post(name: .flushPendingSaves, object: nil)

        // The save should happen synchronously on the main thread now
        let data = note.rtfData
        XCTAssertFalse(data.isEmpty)
        let restored = try NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
        XCTAssertEqual(restored.string, "Flushed Text")
    }
}
