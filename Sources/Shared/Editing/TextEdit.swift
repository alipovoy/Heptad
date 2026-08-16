import Foundation

#if canImport(UIKit)
    import UIKit
#else
    import AppKit
#endif

/// A replacement to make in a text view, in the view's own UTF-16 coordinates.
///
/// Shared by every command that edits text rather than attributes: list continuation and
/// checkboxes. The rule that produces one is pure string work and is what the tests drive;
/// applying it belongs to the platform text views, which are what put it on the per-note undo
/// stack.
///
/// The caret is left where the text system puts it, at the end of the replacement, which is where
/// both commands want it. Since #124 the formatting commands change no characters, so nothing needs
/// to override that.
struct TextEdit: Equatable {
    let range: NSRange
    let replacement: String
}

// Both branches insert with the attributes the caller names, because every edit reaching here is
// markup — a list marker continued onto a new line, a checkbox flipped — never formatting the user
// applied.
//
// A bare string dropped into an attributed buffer inherits the run it lands in, so Return at the
// end of `- **item**` gave the new line a bold `- `, which is `**-** ` in the store: the line stops
// being a list item. In formatted mode the traits are the note, and nothing re-derives them.
#if canImport(UIKit)
    extension UITextView {
        /// Applies `edit` through the text input system, which is what registers it for undo.
        /// Mutating `textStorage` directly would leave the step un-undoable.
        ///
        /// The input system inserts with `typingAttributes`, so those are what carry `attributes`
        /// in. They are left as the marker's afterwards: the caret is on a fresh list item, not
        /// continuing the bold run the last one ended with.
        func apply(_ edit: TextEdit, attributes: [NSAttributedString.Key: Any]) {
            guard let start = position(from: beginningOfDocument, offset: edit.range.location),
                let end = position(from: start, offset: edit.range.length),
                let range = textRange(from: start, to: end)
            else { return }

            typingAttributes = attributes
            replace(range, withText: edit.replacement)
        }
    }
#else
    extension NSTextView {
        /// Applies `edit` through the view's own change hooks, so the per-note undo manager
        /// records it as one step.
        func apply(_ edit: TextEdit, attributes: [NSAttributedString.Key: Any]) {
            guard let textStorage,
                shouldChangeText(in: edit.range, replacementString: edit.replacement)
            else { return }

            textStorage.replaceCharacters(
                in: edit.range,
                with: NSAttributedString(string: edit.replacement, attributes: attributes))
            didChangeText()

            typingAttributes = attributes
        }
    }
#endif
