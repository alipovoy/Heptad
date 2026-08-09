import Testing
import UIKit

@testable import Heptad

/// The caret across a load — the one piece of editor behaviour the two platforms do not share,
/// and so the one piece the macOS suites cannot cover.
///
/// `load(markdown:)` replaces the whole buffer, which happens on every mode switch and every zoom
/// that follows one. AppKit leaves the selection alone when that happens; UIKit collapses it to
/// the end. Without the save and restore around the call, every switch would drop the caret at
/// the bottom of the note while the user was typing in the middle of it.
@MainActor
struct MarkdownTextViewSelectionTests {

    private func textView(_ markdown: String) -> MarkdownTextView {
        let textView = MarkdownTextView()
        textView.load(markdown: markdown)
        return textView
    }

    @Test func loadingKeepsTheCaretWhereItWas() {
        let view = textView("keys and more")
        let caret = NSRange(location: 4, length: 0)
        view.selectedRange = caret

        view.load(markdown: "keys and more")

        #expect(view.selectedRange == caret, "A load must not move the caret")
    }

    /// A mode switch is a load, so the caret survives it — clamped, because the two shapes of the
    /// note are different lengths and an offset into one may be past the end of the other.
    @Test(.bug(id: 124)) func switchingModesKeepsTheCaretInsideTheNote() {
        let view = textView("**keys**")
        view.selectedRange = NSRange(location: 4, length: 0)

        view.apply(MarkdownStyling.Appearance(plainText: true, fontSize: 16))

        #expect(view.text == "**keys**", "Plain mode shows the source")
        #expect(view.selectedRange.location <= (view.text as NSString).length)
    }

    /// A load still has to leave the note drawn — the caret restore must not be undoing the
    /// parse along with the collapse.
    @Test func theTextIsStillStyledAfterTheCaretIsPutBack() throws {
        let view = textView("**keys**")
        view.selectedRange = NSRange(location: 2, length: 0)

        view.load(markdown: "**keys**")

        let font = try #require(
            view.textStorage.attribute(.font, at: 2, effectiveRange: nil) as? UIFont)
        #expect(font.isBold)
    }

    @Test func loadingAnEmptyNoteLeavesTheCaretAtTheStart() {
        let view = textView("")

        view.load(markdown: "")

        #expect(view.selectedRange == NSRange(location: 0, length: 0))
    }
}
