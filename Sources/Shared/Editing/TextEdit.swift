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

#if canImport(UIKit)
    extension UITextView {
        /// Applies `edit` through the text input system, which is what registers it for undo.
        /// Mutating `textStorage` directly would leave the step un-undoable.
        func apply(_ edit: TextEdit) {
            guard let start = position(from: beginningOfDocument, offset: edit.range.location),
                let end = position(from: start, offset: edit.range.length),
                let range = textRange(from: start, to: end)
            else { return }

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
        ///
        /// The replacement is a bare string rather than an attributed one: a note's styling is
        /// derived from its text and reapplied after every change, so there are no attributes
        /// worth carrying into an edit. See `MarkdownStyling`.
        func apply(_ edit: TextEdit) {
            guard let textStorage,
                shouldChangeText(in: edit.range, replacementString: edit.replacement)
            else { return }

            textStorage.replaceCharacters(in: edit.range, with: edit.replacement)
            didChangeText()

            if let selection = edit.selection {
                setSelectedRange(selection)
            }
        }
    }
#endif
