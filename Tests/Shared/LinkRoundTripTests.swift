import Foundation
import Testing

@testable import Heptad

/// The round trip, where a link is involved.
///
/// Split from `RichTextRoundTripTests` because a link is the one construct whose label is not
/// parsed and whose destination is not drawn: the writer builds the brackets out of raw
/// characters, so the ladder that rewrites a line it cannot spell has less room here than
/// anywhere else, and the label is where the parser's escapes and the writer's meet.
struct LinkRoundTripTests {

    private let appearance = MarkdownStyling.Appearance(
        plainText: false, fontSize: AppConstants.Layout.defaultFontSize)

    private func rendered(_ markdown: String) -> NSMutableAttributedString {
        NSMutableAttributedString(
            attributedString: RichTextRendering.attributed(from: markdown, appearance: appearance))
    }

    private func roundTrip(_ markdown: String) -> String {
        MarkdownWriting.markdown(from: rendered(markdown))
    }

    private func roundTripIsStable(_ markdown: String) -> Bool {
        roundTrip(markdown) == markdown
    }

    @Test func aLinkCarriesItsDestination() throws {
        let text = rendered("[docs](https://example.com)")

        #expect(text.string == "docs")
        let destination = text.attribute(.link, at: 0, effectiveRange: nil) as? String
        #expect(destination == "https://example.com")
    }

    /// A link this app cannot spell used to be written anyway, permanently changing the note's
    /// own text: the escaping candidate is byte-identical for a link — `emit` builds the brackets
    /// and the destination out of raw characters — so the check found the line wrong and had
    /// nothing else to write.
    ///
    /// Now the ladder ends somewhere. The link is lost, which is the most this app can do with a
    /// destination it has no spelling for, but not one character of the note is.
    @Test(arguments: ["", "https://e.co/a)b", "x\ny"])
    func aLinkWithAnUnspellableDestinationLosesTheLinkAndNotTheText(_ destination: String) {
        let text = rendered("")
        text.replaceCharacters(in: NSRange(location: 0, length: 0), with: "Foo bar")
        text.addAttribute(.link, value: destination, range: NSRange(location: 0, length: 7))

        let written = MarkdownWriting.markdown(from: text)

        #expect(rendered(written).string == "Foo bar")
        #expect(roundTripIsStable(written), "and it is not written differently the second time")
    }

    /// An italic link with no room for `_` is spelled with `*`, rather than costing the note its
    /// destination.
    ///
    /// The pair around a link used to be written from `Emphasis.delimiter` alone, so every rung of
    /// the ladder produced the same bytes for this line and all six were rejected — and what a
    /// line the ladder cannot spell falls to is `Spelling.plain`, which writes the label's
    /// characters and no brackets at all. The URL was gone from the note on the next save, with
    /// `x*[a](u)*y` sitting right there as a spelling that reads back exactly.
    @Test(
        arguments: [
            "x*[a](u)*y",  // word characters on both sides refuse `_`
            "x*[a](u)*",  // and on one side is enough
            // A guard row rather than a regression row: the bold pair is itself the boundary `_`
            // needs, so this line was already written correctly — what it pins is that a link
            // carrying two traits still nests them in order once each one is chosen separately.
            "x**_[a](u)_**y"
        ])
    func anItalicLinkKeepsItsDestinationWhereverItSits(_ source: String) throws {
        let text = rendered(source)

        // The label, wherever the bold around it put it — and rendered as a link carrying italic,
        // which is the premise the three rows share.
        let italic = (text.string as NSString).range(of: "a").location
        #expect(Emphasis.emphasis.isOn(text.attributes(at: italic, effectiveRange: nil)))
        #expect(text.attribute(.link, at: italic, effectiveRange: nil) != nil)

        let written = MarkdownWriting.markdown(from: text)

        #expect(
            rendered(written).attribute(.link, at: italic, effectiveRange: nil) != nil,
            "\(written) — the destination survives the save")
        #expect(roundTripIsStable(written), "and is not written differently the second time")
    }

    /// A link that reaches the end of its line still gets written.
    ///
    /// The attribute carries the terminator — the shape a link arrives in when it is dragged over
    /// or pasted with the line break — and the writer used to see a newline in the label and give
    /// up, which meant a link survived only on the note's *last* line, where there is no
    /// terminator to carry.
    @Test func aLinkThatRunsToTheEndOfALineIsStillWritten() {
        let text = rendered("")
        text.replaceCharacters(in: NSRange(location: 0, length: 0), with: "docs\nnext")
        text.addAttribute(.link, value: "https://e.co", range: NSRange(location: 0, length: 5))

        #expect(MarkdownWriting.markdown(from: text) == "[docs](https://e.co)\nnext")
    }

    /// A label holding a bracket keeps its link, and its characters.
    ///
    /// The writer escapes the `]` so the parser finds the right one, and the parser honoured that
    /// escape without hiding it — so the escaped candidate read back as different characters, the
    /// ladder dropped the link to get the text right, and the note lost a link on every save. The
    /// rung below that keeps the characters, which is why this cost a link and not a word.
    @Test(arguments: ["a]b", "a[b", "a\\b", "]", "a]b]c"])
    func aLabelHoldingSyntaxKeepsItsLink(label: String) {
        let text = rendered("")
        text.replaceCharacters(in: NSRange(location: 0, length: 0), with: label)
        text.addAttribute(
            .link, value: "https://e.co", range: NSRange(location: 0, length: label.utf16.count))

        let written = MarkdownWriting.markdown(from: text)

        #expect(written.hasSuffix("](https://e.co)"), "the link is written")
        #expect(rendered(written).string == label, "and costs the label no characters")
        #expect(roundTripIsStable(written), "and the spelling is a fixed point")
    }

    /// The label's link survives the escape, rather than the escape splitting it in two.
    @Test func anEscapedBracketStaysInsideTheLink() throws {
        let text = rendered("[a\\]b](https://e.co)")

        #expect(text.string == "a]b")
        for location in 0..<text.length {
            #expect(text.attribute(.link, at: location, effectiveRange: nil) != nil)
        }
    }
}
