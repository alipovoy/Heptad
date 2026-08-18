import Testing
import UIKit

@testable import Heptad

/// The caret across a load — the one piece of editor behaviour the two platforms do not share,
/// and so the one piece the macOS suites cannot cover.
///
/// `load(markdown:)` replaces the whole buffer, which happens on every mode switch and every zoom
/// that follows one. What UIKit does with the selection when that happens is **measured, not
/// assumed**, because the assumption this suite was written on turned out to be wrong:
///
/// - A raw `textStorage.setAttributedString` *preserves* the selection, in a detached view and in
///   one that is first responder in a key window alike. It does not collapse it to the end.
/// - A location past the end of the new text is clamped by UIKit itself, so `load`'s own
///   `min(caret.location, length)` is belt and braces rather than the thing standing between the
///   user and a stranded caret. Kept, because that clamp is undocumented and free.
///
/// So the one thing `load` does that UIKit would not is collapse a *selection* to a caret at its
/// head, and that is the only assertion here that can fail. The two clamp tests below pin the
/// guarantee rather than the line — they pass whether the clamp is ours or UIKit's — and say so.
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

    /// A selection comes back as a caret at its head.
    ///
    /// The one observable thing `load`'s save and restore does: measured, a raw
    /// `setAttributedString` leaves `{2, 6}` exactly as it was, and `load` reports `{2, 0}`.
    /// Collapsing is the right answer — the run the selection covered is not the run at those
    /// offsets after a mode switch — and this is the assertion that fails if the restore goes.
    @Test func loadingCollapsesASelectionToACaretAtItsHead() {
        let view = textView("keys and more")
        view.selectedRange = NSRange(location: 2, length: 6)

        view.load(markdown: "keys and more")

        #expect(view.selectedRange == NSRange(location: 2, length: 0))
    }

    /// A mode switch is a load, so the caret survives it — clamped, because the two shapes of the
    /// note are different lengths and an offset into one may be past the end of the other.
    ///
    /// Switched *out* of plain mode, which is the direction that can overrun: the source is longer
    /// than what it draws, so a caret at the end of `**keys**` is four past the end of `keys`.
    ///
    /// A guarantee, not a line — see the note at the top of the file. UIKit clamps this itself, so
    /// this passes with `load`'s own clamp deleted; what it defends is that the caret is never
    /// stranded, by whichever of the two does it.
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

    /// A caret past the end of the note being loaded lands at the start of it.
    ///
    /// Loaded over a *longer* note, because an empty buffer can only hold `(0, 0)` — the previous
    /// version of this test loaded `""` over `""` and so asserted the only answer the type allows.
    /// Also a guarantee rather than a line, for the reason above.
    @Test func loadingAShorterNoteBringsTheCaretBackInside() {
        let view = textView("keys and more")
        view.selectedRange = NSRange(location: 10, length: 0)

        view.load(markdown: "")

        #expect(view.selectedRange == NSRange(location: 0, length: 0))
    }
}
