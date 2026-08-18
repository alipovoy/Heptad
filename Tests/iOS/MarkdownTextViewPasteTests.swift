import Testing
import UIKit

@testable import Heptad

/// What ⌘V puts in the buffer: the other half of `MarkdownTextViewCopyTests`.
///
/// The pair has to agree — the clipboard leaves this app as markdown source, so a paste that took
/// the characters literally turned a copied bold run into the six characters of `**bold**`, which
/// the next save escaped into the store.
///
/// Asserted on `paste(markdown:)` rather than on `paste(_:)`, for the reason the copy suite asserts
/// on `markdownForSelection`: `UIPasteboard.general` is a system service this process cannot depend
/// on reaching.
@MainActor
struct MarkdownTextViewPasteTests {

    private func textView(_ markdown: String = "", plainText: Bool = false) -> MarkdownTextView {
        let view = MarkdownTextView()
        view.apply(MarkdownStyling.Appearance(plainText: plainText, fontSize: 16))
        view.load(markdown: markdown)
        return view
    }

    /// The round trip a copy and a paste inside the same note make.
    @Test func aPastedRunArrivesAsWhatItDescribes() {
        let view = textView()

        view.paste(markdown: "pass: **rotate-me**")

        #expect(view.text == "pass: rotate-me")
        #expect(view.textStorage.carrying(.strong) == "......#########")
    }

    /// Every trait with a spelling, and the marker of a list line, in one paste.
    @Test func aPastedNoteKeepsEverythingTheWriterCanSpell() {
        let source = "- [ ] rotate ~~the~~ _keys_"
        let view = textView()

        view.paste(markdown: source)

        #expect(view.markdown == source, "and is written back as what was copied")
    }

    /// A pasted link arrives as a link, not as its brackets.
    @Test func aPastedLinkKeepsItsDestination() throws {
        let view = textView()

        view.paste(markdown: "see [docs](https://e.co)")

        #expect(view.text == "see docs")
        let destination = view.textStorage.attribute(.link, at: 4, effectiveRange: nil)
        #expect(MarkdownWriting.destination(destination) == "https://e.co")
    }

    /// The paste replaces the selection, as any insertion does.
    @Test func aPasteReplacesTheSelection() {
        let view = textView("keep this")

        view.selectedRange = NSRange(location: 5, length: 4)
        view.paste(markdown: "**that**")

        #expect(view.text == "keep that")
        #expect(view.textStorage.carrying(.strong) == ".....####")
    }

    /// What is typed after a pasted bold run is not itself bold: the caret keeps the attributes it
    /// had, rather than inheriting the last run of the paste.
    @Test func typingAfterAPastedRunContinuesInTheNotesOwnFace() throws {
        let view = textView()

        view.paste(markdown: "**bold**")
        view.insertText("plain")

        #expect(view.text == "boldplain")
        #expect(view.textStorage.carrying(.strong) == "####.....")
    }

    /// In plain mode the buffer is the source, so a paste is the characters as they are — the
    /// symmetry with `copyingInPlainModeTakesTheCharactersAsTheyAre`. `paste(_:)` sends that mode
    /// to `super`; this pins the decision rather than the route.
    @Test func pastingInPlainModeTakesTheCharactersAsTheyAre() {
        let view = textView(plainText: true)

        view.paste(markdown: "pass: **rotate-me**")

        #expect(view.text == "pass: **rotate-me**")
    }

    /// An undo takes the whole paste back, not one run of it.
    @Test func undoTakesTheWholePasteBack() {
        let view = textView("keys")
        view.selectedRange = NSRange(location: 4, length: 0)

        view.paste(markdown: " **rotate** ~~the~~ _keys_")
        #expect(view.text != "keys")

        view.undoManager?.undo()

        #expect(view.text == "keys")
    }
}
