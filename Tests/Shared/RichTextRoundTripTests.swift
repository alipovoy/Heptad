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
            "[wiki](https://en.wikipedia.org/wiki/Foo_(bar))",
            "- one\n- two\n- three",
            "- [ ] rotate **keys**\n- [x] done",
            "1. first\n2. second",
            "**one**\nplain\n_two_",
            "AWS_SECRET_KEY=abc",
            "Test*ing* here",
            "foo*bar*",
            "2 * 3 * 4",
            "chmod +x *.sh here",
            "trailing spaces   \nand a tab\tinside",
            "\\*\\*not bold\\*\\*",
            "- [ ] \\*\\*not bold\\*\\*",
            "\\_not italic\\_ but **this is**",
            "C:\\Users\\admin",
            "a \\ b"
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

    /// Plain mode is the other half of the switch: it shows the source, so it parses nothing.
    @Test func plainModeRendersTheSourceVerbatim() {
        let plain = MarkdownStyling.Appearance(
            plainText: true, fontSize: AppConstants.Layout.defaultFontSize)

        let text = RichTextRendering.attributed(from: "**keys**", appearance: plain)

        #expect(text.string == "**keys**")
        #expect(text.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont == plain.baseFont)
    }

    // MARK: - Escapes

    /// The reason escapes exist: a user types the asterisks *as* asterisks in formatted mode, and
    /// a save that turned them into a bold run would be the app rewriting the note behind them.
    @Test(.bug(id: 124), arguments: [
        "**bold**", "_italic_", "~~struck~~", "[docs](https://example.com)", "a \\* b"
    ])
    func markdownTypedAsTextComesBackAsText(typed: String) {
        let text = rendered("")
        text.replaceCharacters(in: NSRange(location: 0, length: 0), with: typed)

        let written = MarkdownWriting.markdown(from: text)

        #expect(written != typed, "The delimiters are escaped on the way out")
        #expect(rendered(written).string == typed, "and come back as the characters they were")
    }

    /// Only the lines that need escaping get them. A note is read in plain mode too, and a
    /// backslash in front of every glob would be its own kind of damage.
    ///
    /// Two arguments, not five: the other three are in `markdownSurvivesTheRoundTrip`'s list and
    /// reach the buffer identically either way — verified byte-for-byte. These two are the ones
    /// that carry information this test alone has.
    @Test(.bug(id: 124), arguments: ["chmod +x *.sh", "50% * 2"])
    func textThatReadsBackAsItselfIsLeftAlone(typed: String) {
        let text = rendered("")
        text.replaceCharacters(in: NSRange(location: 0, length: 0), with: typed)

        #expect(MarkdownWriting.markdown(from: text) == typed)
    }

    /// A backslash that protects nothing is dropped on the way out, because the parser reads
    /// `\\\\` and `\\` as the same one character. The note is unchanged; only its spelling is.
    @Test func aRedundantEscapeIsWrittenInItsShorterSpelling() {
        #expect(rendered("escaped \\\\ backslash").string == "escaped \\ backslash")
        #expect(roundTrip("escaped \\\\ backslash") == "escaped \\ backslash")
    }

    /// The escaping stops short of the line's own list marker.
    ///
    /// `- [ ] ` is content — the user typed it, or pressed Return and had it typed for them — so
    /// a backslash through it is not a defence against anything. It demoted the checkbox to a
    /// bare bullet in the stored file, and the item stopped being a task on the first save that
    /// escaped its line.
    @Test(arguments: ["- [ ] ", "- [x] ", "- ", "1. ", "  - "])
    func escapingALineLeavesItsListMarkerAlone(marker: String) {
        let text = rendered("")
        text.replaceCharacters(in: NSRange(location: 0, length: 0), with: marker + "**not bold**")

        let written = MarkdownWriting.markdown(from: text)

        #expect(written == marker + "\\*\\*not bold\\*\\*")
        #expect(
            ListContinuation.markerLength(on: written) == marker.utf16.count,
            "and the line still reads as the list item it was")
    }

    /// Escaping is decided per line, so one awkward line does not put backslashes through the
    /// whole note.
    @Test(.bug(id: 124)) func onlyTheLineThatNeedsEscapingGetsIt() {
        let text = rendered("")
        text.replaceCharacters(in: NSRange(location: 0, length: 0), with: "2 * 3\n**not bold**")

        #expect(MarkdownWriting.markdown(from: text) == "2 * 3\n\\*\\*not bold\\*\\*")
    }

    /// The case no rule about the plain text alone would have caught: text ending in `*` next to
    /// a bold run writes `a***b**`, which reads back as a bold `*b`. Only writing it and reading
    /// it again finds that, which is what the writer does.
    @Test(.bug(id: 124)) func aRunBesideALooseDelimiterIsEscaped() throws {
        let text = rendered("")
        text.replaceCharacters(in: NSRange(location: 0, length: 0), with: "a*b")
        MarkdownStyling.restyle(text, over: NSRange(location: 2, length: 1)) { $0.bolded() }

        let written = MarkdownWriting.markdown(from: text)
        let read = rendered(written)

        #expect(read.string == "a*b")
        let font = try #require(read.attribute(.font, at: 1, effectiveRange: nil) as? PlatformFont)
        #expect(font.isBold == false, "The loose asterisk is not swallowed into the bold run")
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

    /// Italic beside another construct.
    ///
    /// The writer used to ask whether a `_` pair would read back by looking at the characters
    /// flanking the run in the *rendered* string — which has no delimiters in it — so the `d` and
    /// the `w` of `hardware` looked adjacent and the pair was refused. In the markdown being
    /// written the `**` sits between them, and the parser reads it back exactly.
    @Test(
        arguments: [
            "the **_hard_**ware", "x**_a_**y", "_a_**b**", "**a**_b_", "~~_a_~~b"
        ])
    func italicSurvivesBesideAnotherConstruct(_ markdown: String) {
        #expect(roundTrip(markdown) == markdown)
    }

    /// And the rule that refusal existed to protect is still kept: `_` inside a word is an
    /// identifier, not italic, so the parser never reads one and the writer never writes one.
    @Test(arguments: ["AWS_SECRET_KEY", "snake_case_name", "__init__"])
    func anUnderscoreInsideAWordIsNotItalic(_ markdown: String) {
        #expect(roundTrip(markdown) == markdown)
    }

    /// Which is what `*` is for. Italic against a word character has no `_` spelling at all, so
    /// the writer used to drop it — ⌘I mid-word showed italic the next save took away.
    @Test(arguments: [
        (NSRange(location: 4, length: 3), "Test*ing*"),  // against the word behind it
        (NSRange(location: 0, length: 4), "*Test*ing"),  // and the word ahead
        (NSRange(location: 2, length: 3), "Te*sti*ng")  // and both
    ])
    func italicAgainstAWordCharacterIsWrittenWithAsterisks(run: NSRange, expected: String) {
        let text = rendered("Testing")
        MarkdownStyling.restyle(text, over: run) { $0.italicized() }

        #expect(MarkdownWriting.markdown(from: text) == expected)
        #expect(roundTripIsStable(expected), "and it reads back as what it was written from")
    }

    /// `_` stays the preferred spelling wherever it reads back, including where the conservative
    /// test says it would not — the `**` between the run and the word is what makes it fine.
    @Test(arguments: ["_keys_", "the **_hard_**ware", "x**_a_**y", "_a_**b**"])
    func underscoreIsKeptWhereverItReadsBack(_ markdown: String) {
        #expect(roundTrip(markdown) == markdown)
    }

    /// A loose asterisk is still an ordinary character. The writer escapes only where it must,
    /// which is decided by writing the line and reading it again.
    @Test(arguments: ["2 * 3 * 4", "chmod +x *.sh", "*.txt and *.md", "SELECT * FROM notes"])
    func aLooseAsteriskIsLeftAsItIs(typed: String) {
        let text = rendered("")
        text.replaceCharacters(in: NSRange(location: 0, length: 0), with: typed)

        #expect(MarkdownWriting.markdown(from: text) == typed)
    }

    /// A run boundary inside a character costs neither the character nor the line's formatting.
    ///
    /// Nothing stops an attribute from starting between the two halves of a surrogate pair, and
    /// `substring(with:)` bridges a half to U+FFFD — `a🔑b` was stored with two replacement
    /// characters in it, which no later edit undoes. The ladder now keeps the characters
    /// whatever happens, so what this pins is the rest: the boundary moves off the pair, and the
    /// line keeps the run it was carrying.
    @Test func aRunBoundaryInsideACharacterDoesNotCostTheCharacter() {
        // The bold starts on the second half of the pair, which is an offset nothing prevents.
        let text = rendered("a🔑b")
        MarkdownStyling.restyle(text, over: NSRange(location: 2, length: 2)) { $0.bolded() }

        #expect(MarkdownWriting.markdown(from: text) == "a**🔑b**")
    }

    // MARK: - Characters a note may not hold

    /// A pasted image's placeholder does not reach the store.
    ///
    /// U+FFFC is what an `NSTextAttachment` contributes to a string, so copying an image and a
    /// word of bold out of Mail brings one along. `normalize` strips the attachment *attribute*
    /// and leaves the character, which is invisible, cannot be selected as anything, and used to
    /// survive every save from then on.
    @Test func anAttachmentPlaceholderIsNotStored() {
        let text = rendered("**caption**")
        text.replaceCharacters(in: NSRange(location: 0, length: 0), with: "\u{FFFC}")

        #expect(MarkdownWriting.markdown(from: text) == "**caption**")
    }

    /// The control characters go the same way, and the line keeps its formatting: they are taken
    /// out before the writer reasons about the line at all, rather than making it a line the
    /// check finds wrong and rewrites as plain text.
    @Test(
        arguments: [
            ("a\u{0}b", "ab"),
            ("a\u{B}b", "ab"),
            ("a\r\nb", "a\nb", ),
            ("a\tb", "a\tb")
        ])
    func aControlCharacterIsNotStored(typed: String, expected: String) {
        let text = rendered("")
        text.replaceCharacters(in: NSRange(location: 0, length: 0), with: typed)

        #expect(MarkdownWriting.markdown(from: text) == expected)
    }

    @Test func filteringACharacterOutDoesNotCostTheLineItsFormatting() {
        let text = rendered("**bold** and _italic_")
        text.replaceCharacters(in: NSRange(location: 4, length: 0), with: "\u{FFFC}")

        #expect(MarkdownWriting.markdown(from: text) == "**bold** and _italic_")
    }

    // MARK: - The line the check rejects twice

    /// A trait with no spelling costs the line itself and nothing else.
    ///
    /// `_c_` between two word characters is an identifier to the parser, so the spelling that
    /// writes it comes back as different characters and is rejected — and the candidate that ends
    /// the ladder holds no delimiters at all, which would take the link with it. Between them is
    /// the rung that drops just the pair it cannot write.
    @Test func aTraitWithNoSpellingDoesNotCostTheLineItsOtherFormatting() {
        let text = rendered("")
        text.replaceCharacters(in: NSRange(location: 0, length: 0), with: "ab cd")
        text.addAttribute(.link, value: "https://e.co", range: NSRange(location: 0, length: 2))
        MarkdownStyling.restyle(text, over: NSRange(location: 3, length: 1)) { $0.italicized() }

        #expect(MarkdownWriting.markdown(from: text) == "[ab](https://e.co) cd")
    }

    private func roundTripIsStable(_ markdown: String) -> Bool {
        roundTrip(markdown) == markdown
    }
}
