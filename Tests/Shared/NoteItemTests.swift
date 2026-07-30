import XCTest

@testable import Heptad

final class NoteItemTests: XCTestCase {
    func testInitialization() {
        let note = NoteItem(id: 0)
        XCTAssertEqual(note.id, 0)
        XCTAssertEqual(note.rtfData, Data())

        let customData = Data("test".utf8)
        let note2 = NoteItem(id: 1, rtfData: customData)
        XCTAssertEqual(note2.id, 1)
        XCTAssertEqual(note2.rtfData, customData)
    }

    func testModifiedAt() {
        let before = Date.now
        let note = NoteItem(id: 0)
        XCTAssertGreaterThanOrEqual(note.modifiedAt, before)
        XCTAssertLessThanOrEqual(note.modifiedAt, .now)

        let stamped = NoteItem(id: 1, modifiedAt: .distantPast)
        XCTAssertEqual(stamped.modifiedAt, .distantPast)
    }
}
