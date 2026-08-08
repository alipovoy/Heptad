import Testing
import UIKit

@testable import Heptad

/// The selection restore around the iOS repaint — the one piece of editor behaviour the two
/// platforms do not share, and so the one piece the macOS suites cannot cover.
///
/// `restyle()` sets attributes across the whole document. AppKit leaves the selection alone when
/// that happens; UIKit collapses it to the end. Without the save and restore around the call,
/// every mode switch and every zoom step would drop the caret at the bottom of the note while the
/// user was typing in the middle of it.
///
/// The line-scoped repaint deliberately has no such dance, because it never touches the whole
/// document — which is why this is about `restyle()` specifically rather than about painting.
@MainActor
struct MarkdownTextViewSelectionTests {

    private func textView(_ text: String) -> MarkdownTextView {
        let textView = MarkdownTextView()
        textView.text = text
        return textView
    }

    @Test func repaintingKeepsTheCaretWhereItWas() {
        let view = textView("**keys** and more")
        let caret = NSRange(location: 4, length: 0)
        view.selectedRange = caret

        view.restyle()

        #expect(view.selectedRange == caret, "A repaint must not move the caret")
    }

    @Test func repaintingKeepsASelection() {
        let view = textView("**keys** and more")
        let selection = NSRange(location: 2, length: 4)
        view.selectedRange = selection

        view.restyle()

        #expect(view.selectedRange == selection)
    }

    /// A repaint still has to leave the note styled — the restore must not be undoing the paint
    /// along with the collapse.
    @Test func theTextIsStillStyledAfterTheSelectionIsRestored() throws {
        let view = textView("**keys**")
        view.selectedRange = NSRange(location: 4, length: 0)

        view.restyle()

        let font = try #require(
            view.textStorage.attribute(.font, at: 2, effectiveRange: nil) as? UIFont)
        #expect(font.fontDescriptor.symbolicTraits.contains(.traitBold))
    }

    /// An empty note takes the early return in `MarkdownStyling.apply` before any attribute is
    /// set, so there is nothing to collapse and nothing to put back.
    @Test func repaintingAnEmptyNoteLeavesTheCaretAtTheStart() {
        let view = textView("")

        view.restyle()

        #expect(view.selectedRange == NSRange(location: 0, length: 0))
    }
}
