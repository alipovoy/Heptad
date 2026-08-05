import Foundation

#if canImport(UIKit)
    import UIKit
#else
    import AppKit
#endif

/// The list-editing rules the editors apply: continuing `- `, `* `, `1. ` and the checkbox
/// forms `- [ ] ` / `- [x] ` on Return, ending the list on an empty item, and flipping a
/// checkbox.
///
/// Pure string work on purpose. The rule is the part worth testing, and the text mutation
/// belongs to the platform text views, which are what put it on the per-note undo stack.
///
/// Explicitly not a Markdown parser: these markers are recognised where a list continuation
/// needs them and nowhere else, and nothing about how notes are stored changes.
enum ListContinuation {
    /// A replacement to make in the text view, in the view's own UTF-16 coordinates.
    struct Edit: Equatable {
        let range: NSRange
        let replacement: String
    }

    /// What Return should do instead of inserting a newline, or nil to let it through.
    static func returnEdit(in text: NSString, selectedRange: NSRange) -> Edit? {
        // A selection means Return replaces something; only a bare caret continues a list.
        guard selectedRange.length == 0 else { return nil }

        let lineRange = text.lineRange(for: selectedRange)
        guard let marker = marker(on: text.substring(with: lineRange)) else { return nil }

        // Return on a marker with nothing after it ends the list rather than growing it.
        guard !marker.contentIsEmpty else {
            return Edit(
                range: NSRange(location: lineRange.location, length: marker.length),
                replacement: "")
        }

        return Edit(range: selectedRange, replacement: "\n" + marker.next)
    }

    /// The flip of the checkbox on the line holding `selectedRange`, or nil when it has none.
    static func checkboxEdit(in text: NSString, selectedRange: NSRange) -> Edit? {
        let lineRange = text.lineRange(for: selectedRange)
        guard let marker = marker(on: text.substring(with: lineRange)),
            let offset = marker.checkboxOffset
        else { return nil }

        return Edit(
            range: NSRange(location: lineRange.location + offset, length: 1),
            replacement: marker.isChecked ? " " : "x")
    }

    // MARK: - Parsing

    private struct Marker {
        /// UTF-16 units the marker occupies at the start of its line, indent included.
        let length: Int

        /// What the next line starts with when the list continues. A checked box continues
        /// as an unchecked one; a number continues as the next number.
        let next: String

        /// Nothing but whitespace follows the marker, which is what ends the list.
        let contentIsEmpty: Bool

        /// UTF-16 offset of the character between the brackets. Checkbox items only.
        let checkboxOffset: Int?

        let isChecked: Bool
    }

    private static func marker(on line: String) -> Marker? {
        // `lineRange(for:)` includes the terminator; the marker never spans it.
        let body = line.trimmingCharacters(in: .newlines)
        let indentEnd = body.firstIndex { $0 != " " && $0 != "\t" } ?? body.endIndex
        let indent = String(body[..<indentEnd])
        let rest = String(body[indentEnd...])

        func make(_ text: String, next: String, checked: Bool? = nil) -> Marker {
            let content = rest.dropFirst(text.count)
            return Marker(
                length: (indent + text).utf16.count,
                next: indent + next,
                contentIsEmpty: content.trimmingCharacters(in: .whitespaces).isEmpty,
                checkboxOffset: checked == nil ? nil : (indent + "- [").utf16.count,
                isChecked: checked ?? false
            )
        }

        if rest.hasPrefix("- ") || rest.hasPrefix("* ") {
            let bullet = String(rest.prefix(2))
            let afterBullet = rest.dropFirst(2)

            // A checkbox is a "- " item whose marker carries on into the brackets.
            for box in ["[ ] ", "[x] ", "[X] "] where bullet == "- " && afterBullet.hasPrefix(box) {
                return make("- " + box, next: "- [ ] ", checked: box != "[ ] ")
            }

            return make(bullet, next: bullet)
        }

        let digits = rest.prefix(while: \.isWholeNumber)
        if !digits.isEmpty, rest.dropFirst(digits.count).hasPrefix(". "), let number = Int(digits) {
            return make(digits + ". ", next: "\(number + 1). ")
        }

        return nil
    }
}

#if canImport(UIKit)
    extension UITextView {
        /// Applies `edit` through the text input system, which is what registers it for undo.
        /// Mutating `textStorage` directly would leave the step un-undoable.
        func apply(_ edit: ListContinuation.Edit) {
            guard let start = position(from: beginningOfDocument, offset: edit.range.location),
                let end = position(from: start, offset: edit.range.length),
                let range = textRange(from: start, to: end)
            else { return }

            replace(range, withText: edit.replacement)
        }
    }
#else
    extension NSTextView {
        /// Applies `edit` through the view's own change hooks, so the per-note undo manager
        /// records it as one step. The inserted text takes the typing attributes rather than
        /// whatever happened to sit at the replacement point.
        func apply(_ edit: ListContinuation.Edit) {
            guard let textStorage,
                shouldChangeText(in: edit.range, replacementString: edit.replacement)
            else { return }

            textStorage.replaceCharacters(
                in: edit.range,
                with: NSAttributedString(string: edit.replacement, attributes: typingAttributes))
            didChangeText()
        }
    }
#endif
