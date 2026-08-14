import Foundation
import Testing

#if canImport(UIKit)
    import UIKit
#else
    import AppKit
#endif

@testable import Heptad

/// The list rules, on their own: what Return does to a line, and what ⌘⇧U does to a checkbox.
/// The text views that apply the results are covered on the macOS side.
struct ListContinuationTests {

    /// Return at the end of `line`, which is the whole text.
    private func returnEdit(atEndOf line: String) -> TextEdit? {
        let text = line as NSString
        return ListContinuation.returnEdit(
            in: text, selectedRange: NSRange(location: text.length, length: 0))
    }

    // MARK: - Continuing a list

    @Test(
        arguments: [
            ("- item", "\n- "),
            ("* item", "\n* "),
            ("1. item", "\n2. "),
            ("9. item", "\n10. "),
            ("- [ ] task", "\n- [ ] "),
            // A checked item continues as an unchecked one: the next thing to do, not a
            // second copy of the thing already done.
            ("- [x] task", "\n- [ ] "),
            ("- [X] task", "\n- [ ] "),
            // Indentation carries, so a nested list stays nested.
            ("    - item", "\n    - "),
            ("\t1. item", "\n\t2. ")
        ])
    func returnContinuesAListItem(line: String, inserted: String) throws {
        let edit = try #require(returnEdit(atEndOf: line))

        #expect(edit.replacement == inserted)
        #expect(edit.range == NSRange(location: (line as NSString).length, length: 0))
    }

    /// The largest number a marker can hold continues as itself rather than trapping. Return on
    /// `9223372036854775807. ` closed the app: an overflow on a keystroke, over a line nothing
    /// stops anyone typing.
    @Test func aMarkerAtTheLargestNumberContinuesWithoutOverflowing() throws {
        let edit = try #require(returnEdit(atEndOf: "\(Int.max). item"))

        #expect(edit.replacement == "\n\(Int.max). ")
    }

    /// One digit further and it is not a number this app can count with, so the line is not a
    /// list at all and Return is left alone.
    @Test func aMarkerTooLargeToCountWithIsNotAList() {
        #expect(returnEdit(atEndOf: "\(Int.max)0. item") == nil)
    }

    /// Return mid-item still continues the list — the item splits in two, both marked.
    @Test func returnContinuesFromInsideTheItem() throws {
        let text = "- item" as NSString

        let edit = try #require(
            ListContinuation.returnEdit(in: text, selectedRange: NSRange(location: 4, length: 0)))

        #expect(edit.replacement == "\n- ")
        #expect(edit.range == NSRange(location: 4, length: 0))
    }

    @Test func returnContinuesTheLineTheCaretIsOn() throws {
        let text = "- first\n- second" as NSString

        let edit = try #require(
            ListContinuation.returnEdit(
                in: text, selectedRange: NSRange(location: text.length, length: 0)))

        #expect(edit.replacement == "\n- ")
    }

    // MARK: - Ending a list

    /// An empty item removes its own marker instead of adding another, which is how a list
    /// stops. The replacement is the marker's range, not the caret's.
    @Test(arguments: ["- ", "* ", "3. ", "- [ ] ", "- [x] ", "  - "])
    func returnOnAnEmptyItemRemovesTheMarker(line: String) throws {
        let edit = try #require(returnEdit(atEndOf: line))

        #expect(edit.replacement.isEmpty)
        #expect(edit.range == NSRange(location: 0, length: (line as NSString).length))
    }

    // MARK: - Leaving Return alone

    @Test(
        arguments: [
            "plain text",
            "-no space after the dash",
            "1.no space after the dot",
            "[ ] a box with no bullet",
            ""
        ])
    func returnIsUntouchedOffAList(line: String) {
        #expect(returnEdit(atEndOf: line) == nil)
    }

    /// Return over a selection replaces it; continuing the list there would drop the
    /// selected text or duplicate the marker, so the plain newline stands.
    @Test func returnOverASelectionIsUntouched() {
        let text = "- item" as NSString

        #expect(
            ListContinuation.returnEdit(in: text, selectedRange: NSRange(location: 2, length: 4))
                == nil)
    }

    // MARK: - Checkboxes

    @Test(arguments: [("- [ ] task", "x"), ("- [x] task", " "), ("- [X] task", " ")])
    func checkboxEditFlipsTheBox(line: String, replacement: String) throws {
        let edit = try #require(
            ListContinuation.checkboxEdit(in: line as NSString, selectedRange: NSRange()))

        #expect(edit.replacement == replacement)
        #expect(edit.range == NSRange(location: 3, length: 1))
    }

    /// The offset is measured from the start of the line, not the start of the text, and the
    /// indent counts toward it.
    @Test func checkboxEditTargetsTheLineTheCaretIsOn() throws {
        let text = "- [ ] first\n  - [x] second" as NSString

        let edit = try #require(
            ListContinuation.checkboxEdit(
                in: text, selectedRange: NSRange(location: text.length, length: 0)))

        #expect(edit.range == NSRange(location: 17, length: 1))
        #expect(edit.replacement == " ")
    }

    @Test(arguments: ["- item", "plain text", "1. item"])
    func checkboxEditIsNilWithoutABox(line: String) {
        #expect(ListContinuation.checkboxEdit(in: line as NSString, selectedRange: NSRange()) == nil)
    }
}
