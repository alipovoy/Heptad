import XCTest

#if os(macOS)
    @testable import SevenNotes_macOS
#else
    @testable import SevenNotes_iOS
#endif

final class NoteItemTests: XCTestCase {
    func testInitialization() {
        let note = NoteItem(id: 0)
        XCTAssertEqual(note.id, 0)
        XCTAssertEqual(note.rtfData, Data())

        let customData = "test".data(using: .utf8)!
        let note2 = NoteItem(id: 1, rtfData: customData)
        XCTAssertEqual(note2.id, 1)
        XCTAssertEqual(note2.rtfData, customData)
    }
}
