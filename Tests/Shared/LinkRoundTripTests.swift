import Foundation
import Testing

@testable import Heptad

/// The round trip, where a link is involved.
///
/// Split from `RichTextRoundTripTests` because a link is the one construct whose label is not
/// parsed and whose destination is not drawn: the writer builds the brackets out of raw
/// characters, so the ladder that rewrites a line it cannot spell has less room here.
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

    /// The escaping rung is byte-identical for a link — `emit` builds the brackets and the
    /// destination out of raw characters — so with nothing below it the writer stored a line it had
    /// found wrong, changing the note's own text. Dropping the link is the rung that ends the
    /// ladder.
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
    /// destination: with the pair around a link written from `Emphasis.delimiter` alone, every rung
    /// produced the same bytes and the line fell to `Spelling.plain`, which writes the label's
    /// characters and no brackets at all.
    @Test(
        arguments: [
            "x *[a](u)* y",  // `_` is refused against a word character; whitespace frees `*`
            "(*[a](u)*)",  // and so does punctuation, on the flanking rule's own terms
            // A guard row: the bold pair is itself the boundary `_` needs, so what it pins is that
            // two traits still nest in order once each is spelled separately.
            "x**_[a](u)_**y"
        ])
    func anItalicLinkKeepsItsDestinationWhereverItSits(_ source: String) throws {
        let text = rendered(source)

        // The label, wherever the bold around it put it.
        let italic = (text.string as NSString).range(of: "a").location
        #expect(Emphasis.emphasis.isOn(text.attributes(at: italic, effectiveRange: nil)))
        #expect(text.attribute(.link, at: italic, effectiveRange: nil) != nil)

        let written = MarkdownWriting.markdown(from: text)

        #expect(
            rendered(written).attribute(.link, at: italic, effectiveRange: nil) != nil,
            "\(written) — the destination survives the save")
        #expect(roundTripIsStable(written), "and is not written differently the second time")
    }

    /// An italic link with a word character right against it keeps its destination and loses the
    /// italic, because there is no spelling left for it.
    ///
    /// `_` is refused by the word boundary, and `*` by the flanking rule — the pair would face the
    /// label's `[` on the inside and the word character on the outside, which is the shape
    /// `/usr/*/bin/*x` has and no parser reads as emphasis. So the ladder reaches `.dropped`, and
    /// what it drops is the trait rather than the URL. `x*[a](u)*y` used to be written here, read
    /// back as italic by this app alone, and shown as its asterisks by everything else.
    @Test func anItalicLinkAgainstAWordCharacterKeepsTheDestinationAndNotTheItalic() throws {
        let text = rendered("xay")
        text.addAttribute(.link, value: "https://e.co", range: NSRange(location: 1, length: 1))
        AttributedFormatting.toggle(
            .emphasis, over: NSRange(location: 1, length: 1), in: text, appearance: appearance)

        let written = MarkdownWriting.markdown(from: text)
        let back = rendered(written)

        #expect(written == "x[a](https://e.co)y")
        #expect(back.string == "xay", "\(written) — the characters are the note's own")
        #expect(back.attribute(.link, at: 1, effectiveRange: nil) != nil, "\(written) — and the URL")
        #expect(
            !Emphasis.emphasis.isOn(back.attributes(at: 1, effectiveRange: nil)),
            "\(written) — the italic is what was given up")
    }

    /// A bold italic link keeps its italic when another run on the line sends the ladder down a
    /// rung.
    ///
    /// The retreat is per *line*, which is why the input carries an `x*i*` prefix: `_i_` against a
    /// word character does not read back, so the whole line reaches `.fallback`, which respelled
    /// the link's `_` as `*` too. `***[a](u)***` resolves in no parser, so that rung failed as well
    /// and `.dropped` took the italic off both runs.
    @Test(arguments: ["x*i***_[a](u)_**y", "x*i***_[ab](u)_**y", "x*i***_[a](u)_**y z"])
    func aBoldLinkKeepsItsItalicWhenAnotherRunSendsTheLineDownTheLadder(_ source: String) throws {
        let text = rendered(source)

        let label = (text.string as NSString).range(of: "a").location
        let traits = text.attributes(at: label, effectiveRange: nil)
        #expect(Emphasis.emphasis.isOn(traits), "the label is italic")
        #expect(Emphasis.strong.isOn(traits), "and bold")
        #expect(traits[.link] != nil, "and a link")

        let written = MarkdownWriting.markdown(from: text)
        let back = rendered(written).attributes(at: label, effectiveRange: nil)

        #expect(Emphasis.emphasis.isOn(back), "\(written) — italic survives the save")
        #expect(Emphasis.strong.isOn(back), "\(written) — and bold")
        #expect(back[.link] != nil, "\(written) — and the destination")
        #expect(roundTripIsStable(written), "and it is not written differently the second time")
    }

    /// A link that reaches the end of its line still gets written.
    ///
    /// The attribute carries the terminator — the shape a dragged or pasted link arrives in — and a
    /// newline in the label stopped the writer, so a link survived only on the note's last line.
    @Test func aLinkThatRunsToTheEndOfALineIsStillWritten() {
        let text = rendered("")
        text.replaceCharacters(in: NSRange(location: 0, length: 0), with: "docs\nnext")
        text.addAttribute(.link, value: "https://e.co", range: NSRange(location: 0, length: 5))

        #expect(MarkdownWriting.markdown(from: text) == "[docs](https://e.co)\nnext")
    }

    /// A label holding a bracket keeps its link, and its characters.
    ///
    /// The writer escapes the `]` so the parser finds the right one; while the parser honoured that
    /// escape without hiding it, the candidate read back as different characters and the ladder
    /// dropped the link to keep the text — a link lost on every save.
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

    /// A link covering a whole checkbox line keeps its destination.
    ///
    /// The marker exemption is a rule about a line that *is* a list line; inside a label there is no
    /// marker, whatever the rendered text shows. Exempting the `[x]` there left its `]` unescaped,
    /// the parser took the label to end at that one, and with every rung writing the same bytes the
    /// line fell to `Spelling.plain` — the destination gone, and gone for good.
    @Test(arguments: ["- [x] task", "- [ ] task", "- task", "1. task", "  - [x] task"])
    func aLinkOverAWholeListLineKeepsItsDestination(line: String) throws {
        let text = rendered("")
        text.replaceCharacters(in: NSRange(location: 0, length: 0), with: line)
        text.addAttribute(
            .link, value: "https://e.co", range: NSRange(location: 0, length: line.utf16.count))

        let written = MarkdownWriting.markdown(from: text)

        #expect(written.hasSuffix("](https://e.co)"), "\(written) — the destination is written")
        #expect(rendered(written).string == line, "\(written) — and costs the label no characters")
        #expect(roundTripIsStable(written), "and the spelling is a fixed point")
    }

    /// And a stored one is not rewritten into a line without it.
    @Test func aStoredLinkOverACheckboxLineIsAFixedPoint() {
        #expect(roundTripIsStable("[- \\[x\\] task](https://e.co)"))
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
