import XCTest

#if os(macOS)
    @testable import SevenNotes_macOS
#else
    @testable import SevenNotes_iOS
#endif

final class NoteContentSaverTests: XCTestCase {

    func testSerializationAndDebouncing() async throws {
        // Arrange
        let note = NoteItem(id: 0)
        let saver = NoteContentSaver(note: note, debounceNanoseconds: 100_000_000)  // 0.1s

        let attrString = NSAttributedString(string: "Hello Test")

        // Act
        saver.save(attributedString: attrString)

        // Wait for debounce + some buffer
        try await Task.sleep(nanoseconds: 200_000_000)

        // Assert
        let data = note.rtfData
        XCTAssertFalse(data.isEmpty)
        let restored = try NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
        XCTAssertEqual(restored.string, "Hello Test")  // RTF doesn't add a trailing newline here
    }

    func testDebounceCancelsPrevious() async throws {
        let note = NoteItem(id: 0)
        let saver = NoteContentSaver(note: note, debounceNanoseconds: 150_000_000)

        let str1 = NSAttributedString(string: "A")
        let str2 = NSAttributedString(string: "AB")
        let str3 = NSAttributedString(string: "ABC")

        saver.save(attributedString: str1)
        saver.save(attributedString: str2)
        saver.save(attributedString: str3)

        try await Task.sleep(nanoseconds: 250_000_000)

        let data = note.rtfData
        XCTAssertFalse(data.isEmpty)
        let restored = try NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
        XCTAssertEqual(restored.string, "ABC")  // RTF doesn't add trailing newline here
    }

    func testEmptyStringOutputsEmptyData() async throws {
        let note = NoteItem(id: 0)
        let saver = NoteContentSaver(note: note, debounceNanoseconds: 50_000_000)

        // Provide empty string
        saver.save(attributedString: NSAttributedString(string: ""))
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(note.rtfData.isEmpty)

        // Provide spaces
        saver.save(attributedString: NSAttributedString(string: "   \n  "))
        XCTAssertTrue(note.rtfData.isEmpty)
    }

    func testFlushImmediatelySavesPending() throws {
        let note = NoteItem(id: 0)
        let saver = NoteContentSaver(note: note, debounceNanoseconds: 5_000_000_000) // 5s debounce

        let str = NSAttributedString(string: "Flushed Text")
        saver.save(attributedString: str)

        // The save is debounced so the note should not have it yet
        XCTAssertTrue(note.rtfData.isEmpty)

        // Simulate notification
        NotificationCenter.default.post(name: .flushPendingSaves, object: nil)

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
