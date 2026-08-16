import Testing
import UIKit

@testable import Heptad

/// The caret across a load — the one piece of editor behaviour the two platforms do not share,
/// and so the one piece the macOS suites cannot cover.
///
/// `load(markdown:)` replaces the whole buffer, which happens on every mode switch and every zoom
/// that follows one. Measured, UIKit preserves the selection across a raw `setAttributedString`
/// and clamps an out-of-range location itself, so the only thing `load` adds is collapsing a
/// selection to a caret at its head. The two clamp tests below therefore pin a guarantee rather
/// than a line: they pass whether the clamp is ours or UIKit's.
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

    /// A selection comes back as a caret at its head: after a mode switch the run it covered is
    /// not the run at those offsets. The one assertion here that fails if the restore goes.
    @Test func loadingCollapsesASelectionToACaretAtItsHead() {
        let view = textView("keys and more")
        view.selectedRange = NSRange(location: 2, length: 6)

        view.load(markdown: "keys and more")

        #expect(view.selectedRange == NSRange(location: 2, length: 0))
    }

    /// A mode switch is a load, so the caret survives it — clamped, because the two shapes of the
    /// note are different lengths. Switched out of plain mode, the direction that can overrun: a
    /// caret at the end of `**keys**` is four past the end of `keys`.
    @Test(.bug(id: 124)) func switchingModesKeepsTheCaretInsideTheNote() {
        let view = textView("**keys**")
        view.apply(MarkdownStyling.Appearance(plainText: true, fontSize: 16))
        #expect(view.text == "**keys**", "Plain mode shows the source")

        view.selectedRange = NSRange(location: 8, length: 0)
        view.apply(MarkdownStyling.Appearance(plainText: false, fontSize: 16))

        #expect(view.text == "keys", "and formatted mode draws it")
        #expect(view.selectedRange.location <= 4, "the caret came back inside the note")
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

    /// A caret past the end of the note being loaded lands at the start of it. The starting buffer
    /// has to be the longer one: an empty buffer can only hold `(0, 0)`, whatever `load` does.
    @Test func loadingAShorterNoteBringsTheCaretBackInside() {
        let view = textView("keys and more")
        view.selectedRange = NSRange(location: 10, length: 0)

        view.load(markdown: "")

        #expect(view.selectedRange == NSRange(location: 0, length: 0))
    }
}
