import Foundation

#if canImport(UIKit)
    import UIKit
#else
    import AppKit
#endif

/// A replacement to make in a text view, in the view's own UTF-16 coordinates.
///
/// Shared by every command that edits text rather than attributes: list continuation,
/// checkboxes, and the markdown formatting commands. The rule that produces one is pure string
/// work and is what the tests drive; applying it belongs to the platform text views, which are
/// what put it on the per-note undo stack.
struct TextEdit: Equatable {
    let range: NSRange
    let replacement: String

    /// Where the selection should land afterwards, in post-edit coordinates, or nil to leave
    /// the caret where the text system puts it — at the end of the replacement.
    ///
    /// Load-bearing for the formatting commands: `⌘B` over a selection has to leave that same
    /// text selected so a second `⌘B` unwraps it, and `⌘B` on a bare caret has to land *between*
    /// the two markers it just inserted rather than after them.
    let selection: NSRange?

    init(range: NSRange, replacement: String, selection: NSRange? = nil) {
        self.range = range
        self.replacement = replacement
        self.selection = selection
    }
}

// Both branches insert with attributes the caller names, and this is the reason. Every edit that
// reaches here is *markup* — a list marker continued onto a new line, a checkbox flipped — and a
// marker is syntax the app wrote, never formatting the user applied.
//
// A bare string dropped into an attributed buffer inherits the run it lands in, so Return at the
// end of `- **item**` gave the new line a bold `- `, which is `**-** ` in the store: the line stops
// being a list item, Return will not continue it, `⌘⇧U` finds no checkbox on it, and a checkbox
// item's own marker is demoted on the way past. The comment that used to sit here — "a note's
// styling is derived from its text and reapplied after every change" — was true before #124, when
// the buffer held source and styling was re-derived by parsing. In formatted mode the traits *are*
// the note, and nothing re-derives them.
#if canImport(UIKit)
    extension UITextView {
        /// Applies `edit` through the text input system, which is what registers it for undo.
        /// Mutating `textStorage` directly would leave the step un-undoable.
        ///
        /// The input system inserts with `typingAttributes`, so those are what carry `attributes`
        /// in. They are left as the marker's afterwards rather than put back: the caret is now
        /// sitting on a fresh list item, and what is typed there is not a continuation of the
        /// bold run the last one ended with.
        func apply(_ edit: TextEdit, attributes: [NSAttributedString.Key: Any]) {
            guard let start = position(from: beginningOfDocument, offset: edit.range.location),
                let end = position(from: start, offset: edit.range.length),
                let range = textRange(from: start, to: end)
            else { return }

            typingAttributes = attributes
            replace(range, withText: edit.replacement)

            if let selection = edit.selection {
                selectedRange = selection
            }
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

            if let selection = edit.selection {
                setSelectedRange(selection)
            }
        }
    }
#endif
