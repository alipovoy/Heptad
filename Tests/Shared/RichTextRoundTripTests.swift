import Foundation
import Testing

@testable import Heptad

/// The conversion formatted mode is built on: markdown in, rich text out, markdown back.
///
/// A note is stored as markdown whichever mode it is edited in, so this pair of functions runs on
/// every load, every save and every mode switch. If it is not lossless, the note rots — which is
/// why most of this suite is one property: what goes in comes back out.
struct RichTextRoundTripTests {

    private let appearance = MarkdownStyling.Appearance(
        plainText: false, fontSize: AppConstants.Layout.defaultFontSize)

    private func rendered(_ markdown: String) -> NSMutableAttributedString {
        NSMutableAttributedString(
            attributedString: RichTextRendering.attributed(from: markdown, appearance: appearance))
    }

    private func roundTrip(_ markdown: String) -> String {
        MarkdownWriting.markdown(from: rendered(markdown))
    }

    // MARK: - The property

    @Test(
        .bug(id: 124),
        arguments: [
            "",
            "plain text",
            "**bold**",
            "_italic_",
            "~~struck~~",
            "**bold** and _italic_ and ~~struck~~",
            "**_both_**",
            "rotate **keys** now",
            "[docs](https://example.com)",
            "see [docs](https://example.com) first",
            "- one\n- two\n- three",
            "- [ ] rotate **keys**\n- [x] done",
            "1. first\n2. second",
            "**one**\nplain\n_two_",
            "AWS_SECRET_KEY=abc",
            "2 * 3 * 4",
            "chmod +x *.sh here",
            "trailing spaces   \nand a tab\tinside"
        ])
    func markdownSurvivesTheRoundTrip(source: String) {
        #expect(roundTrip(source) == source)
    }

    // MARK: - What the user sees

    /// The delimiters are not hidden, they are *gone*: nothing in the buffer for a caret to stall
    /// on or a backspace to break in half.
    @Test(.bug(id: 124)) func theDelimitersAreNotInTheBuffer() {
        #expect(rendered("**keys**").string == "keys")
        #expect(rendered("see [docs](https://example.com)").string == "see docs")
        #expect(rendered("**bold** and _italic_").string == "bold and italic")
    }

    /// A bullet is content, so it stays exactly as typed — the grey `- ` was the reported half
    /// of #124.
    @Test(.bug(id: 124)) func bulletsStayInTheText() throws {
        let list = rendered("- [ ] rotate **keys**")

        #expect(list.string == "- [ ] rotate keys")

        let bullet = try #require(list.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont)
        #expect(bullet == appearance.baseFont, "in the body font, like the text it introduces")
    }

    @Test func aBoldRunIsBoldAndTheRestIsNot() throws {
        let text = rendered("**keys** here")

        let bold = try #require(text.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont)
        let plain = try #require(text.attribute(.font, at: 6, effectiveRange: nil) as? PlatformFont)

        #expect(bold.isBold)
        #expect(plain.isBold == false)
    }

    @Test func nestedConstructsKeepBothTraits() throws {
        let text = rendered("**_keys_**")

        let font = try #require(text.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont)
        #expect(font.isBold)
        #expect(font.isItalic)
    }

    @Test func aLinkCarriesItsDestination() throws {
        let text = rendered("[docs](https://example.com)")

        #expect(text.string == "docs")
        let destination = text.attribute(.link, at: 0, effectiveRange: nil) as? String
        #expect(destination == "https://example.com")
    }

    /// Plain mode is the other half of the switch: it shows the source, so it parses nothing.
    @Test func plainModeRendersTheSourceVerbatim() {
        let plain = MarkdownStyling.Appearance(
            plainText: true, fontSize: AppConstants.Layout.defaultFontSize)

        let text = RichTextRendering.attributed(from: "**keys**", appearance: plain)

        #expect(text.string == "**keys**")
        #expect(text.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont == plain.baseFont)
    }

    // MARK: - What the writer refuses to spell

    /// A construct never spans lines, so a run dragged across a paragraph is written as one pair
    /// per line. `**one\ntwo**` is markdown this app's parser would never read back.
    @Test func aRunAcrossLinesIsWrittenLineByLine() {
        let text = rendered("one\ntwo")
        MarkdownStyling.restyle(text, over: NSRange(location: 0, length: text.length)) { $0.bolded() }

        #expect(MarkdownWriting.markdown(from: text) == "**one**\n**two**")
    }

    /// A delimiter never closes against whitespace, so the space at the edge of a run is written
    /// outside the pair — `**bold **` renders as four literal asterisks.
    @Test func whitespaceAtTheEdgeOfARunIsWrittenOutsideIt() {
        let text = rendered("bold here")
        MarkdownStyling.restyle(text, over: NSRange(location: 0, length: 5)) { $0.bolded() }

        #expect(MarkdownWriting.markdown(from: text) == "**bold** here")
    }

    /// Overlapping runs cannot be written as overlapping delimiters — markdown has no spelling
    /// for `**a _b**c_`. The fixed nesting order splits the inner one instead.
    @Test func overlappingRunsComeOutNested() {
        let text = rendered("abc def ghi")
        MarkdownStyling.restyle(text, over: NSRange(location: 0, length: 7)) { $0.bolded() }
        MarkdownStyling.restyle(text, over: NSRange(location: 4, length: 7)) { $0.italicized() }

        let markdown = MarkdownWriting.markdown(from: text)

        #expect(markdown == "**abc _def_** _ghi_")
        #expect(roundTripIsStable(markdown), "and what it writes parses back to the same thing")
    }

    private func roundTripIsStable(_ markdown: String) -> Bool {
        roundTrip(markdown) == markdown
    }
}
