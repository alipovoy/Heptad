import Foundation
import Testing

@testable import Heptad

/// The parser that decides what a note looks like: which characters are markdown and which are
/// just characters.
///
/// Worth pinning closely because it is the app's whole formatting vocabulary. Anything it
/// recognises, a command can produce and remove; anything it does not is text. The deliberate
/// limits — one spelling per construct, no spanning lines, no escapes, no parsing inside a
/// link's label — are tested as limits rather than left to be discovered as bugs.
struct MarkdownSyntaxTests {

    private func spans(_ text: String) -> [MarkdownSyntax.Span] {
        MarkdownSyntax.spans(in: text as NSString)
    }

    /// The styled ranges, as the substrings they cover — the readable form of an assertion that
    /// would otherwise be a list of offsets. Syntax of either kind is left out; the two helpers
    /// below are what pin that.
    private func styled(_ text: String) -> [(String, MarkdownSyntax.Style)] {
        spans(text)
            .filter { $0.style != .marker && $0.style != .listMarker }
            .map { ((text as NSString).substring(with: $0.range), $0.style) }
    }

    private func markers(_ text: String) -> [String] {
        substrings(of: .marker, in: text)
    }

    private func listMarkers(_ text: String) -> [String] {
        substrings(of: .listMarker, in: text)
    }

    private func substrings(of style: MarkdownSyntax.Style, in text: String) -> [String] {
        spans(text)
            .filter { $0.style == style }
            .map { (text as NSString).substring(with: $0.range) }
    }

    // MARK: - The vocabulary

    @Test(arguments: [
        ("**bold**", "bold", MarkdownSyntax.Style.strong),
        ("_italic_", "italic", .emphasis),
        ("~~struck~~", "struck", .strikethrough)
    ])
    func delimitedRunsAreStyled(text: String, content: String, style: MarkdownSyntax.Style) {
        #expect(styled(text).map(\.0) == [content])
        #expect(styled(text).map(\.1) == [style])
    }

    /// The delimiters are spans of their own, which is what formatted mode drops: they describe
    /// the run beside them, and rich text carries that description in its attributes instead.
    @Test func delimitersAreReportedAsMarkers() {
        #expect(markers("**bold**") == ["**", "**"])
    }

    @Test func linksStyleTheirLabelAndMarkTheRest() {
        #expect(styled("[docs](https://example.com)").map(\.0) == ["docs"])
        #expect(styled("[docs](https://example.com)").map(\.1) == [.link])
        #expect(markers("[docs](https://example.com)") == ["[", "](https://example.com)"])
    }

    /// A destination's own parentheses are balanced, so the address survives whole. Stopping at the
    /// first `)` gave `[Foo](…/Foo_(bar))` a dead URL, left `)` behind as text, and the writer
    /// stored that.
    @Test(
        arguments: [
            "https://en.wikipedia.org/wiki/Foo_(bar)",
            "https://e.co/a(b(c)d)e",
            "https://e.co/()"
        ])
    func aDestinationMayHoldBalancedParentheses(destination: String) {
        let text = "[Foo](" + destination + ")"

        #expect(styled(text).map(\.0) == ["Foo"])
        #expect(markers(text) == ["[", "](" + destination + ")"])
    }

    /// An unmatched `(` opens a nesting the line never closes, so there is no link — the same
    /// answer as for `[Foo](` with no `)` at all.
    @Test func anUnclosedNestingIsNotALink() {
        #expect(styled("[Foo](https://e.co/(a)").contains { $0.1 == .link } == false)
    }

    /// An unmatched `)` still ends the destination there, so `…/a)b` is an address this app has no
    /// spelling for. `LinkRoundTripTests` pins that the writer never stores one: it drops the link
    /// and keeps every character.
    @Test func anUnmatchedCloseEndsTheDestination() {
        #expect(markers("[Foo](https://e.co/a)b)") == ["[", "](https://e.co/a)"])
    }

    /// The list grammar comes from `ListContinuation`, so what Return continues and what the
    /// editor reads as a bullet are the same set by construction.
    ///
    /// A bullet is its own style rather than a `marker`, and #124 is the difference: markers are
    /// dropped when a note is rendered, and a list whose bullets went with them is not a list.
    @Test(.bug(id: 124), arguments: ["- ", "* ", "1. ", "- [ ] ", "- [x] ", "  - "])
    func listMarkersAreTheirOwnStyleRatherThanDroppableSyntax(marker: String) {
        #expect(listMarkers(marker + "item") == [marker])
        #expect(markers(marker + "item").isEmpty, "A bullet is content, not a delimiter")
    }

    @Test func aRunInsideAListItemIsStillStyled() {
        #expect(styled("- [ ] rotate **keys**").map(\.0) == ["keys"])
    }

    // MARK: - What is not markdown

    /// The flanking rule, which is what keeps arithmetic and shell globs out of the parser.
    @Test(arguments: ["2 * 3 * 4", "chmod +x *.sh here", "a ~~ b ~~ c"])
    func delimitersAroundWhitespaceStyleNothing(text: String) {
        #expect(styled(text).isEmpty)
    }

    @Test(arguments: ["**unclosed", "_also unclosed", "[label](no-paren", "[]()", "****"])
    func incompleteConstructsStyleNothing(text: String) {
        #expect(styled(text).isEmpty)
    }

    /// The rule that makes `_` safe to spell italic with. An underscore inside a word belongs to
    /// the word — these notes are full of keys and identifiers, and italicising the middle of
    /// `AWS_SECRET_KEY` would be the app corrupting the one thing it is for.
    ///
    /// `__init__` is the case that needs `_` itself to count as a word character: the first
    /// underscore is refused for being doubled, and without this rule the second one would open
    /// a run the first was denied.
    @Test(arguments: [
        "AWS_SECRET_KEY", "snake_case_name", "some_var", "a_b",
        "__init__", "__all__", "__", "___"
    ])
    func underscoresInsideWordsAreOrdinaryCharacters(text: String) {
        #expect(styled(text).isEmpty)
    }

    /// The flanking rule cuts both ways: at a word boundary `_` is a delimiter again.
    @Test(arguments: ["_keys_", "rotate _keys_", "_keys_ rotate", "(_keys_)", "**_keys_**"])
    func underscoresAtWordBoundariesStillDelimit(text: String) {
        #expect(styled(text).map(\.0).contains("keys"))
    }

    /// Constructs never span lines, so a stray delimiter spoils at most its own line.
    @Test func aDelimiterDoesNotCloseOnTheNextLine() {
        #expect(styled("**start\nend**").isEmpty)
    }

    @Test func eachLineIsParsedOnItsOwn() {
        #expect(styled("**one**\nplain\n_two_").map(\.0) == ["one", "two"])
    }

    /// `*` is a prefix of `**`, so `**` is matched first: a bold pair is one construct, never two
    /// italic ones around an empty run.
    @Test func boldIsOneConstructRatherThanTwo() {
        #expect(styled("**bold**").map(\.1) == [.strong])
    }

    /// The second spelling of italic, which is what `MarkdownWriting` falls back to where `_`
    /// cannot be written — against a word character.
    @Test(arguments: ["*italic*", "Test*ing*", "foo*bar*"])
    func asterisksSpellItalicToo(text: String) {
        #expect(styled(text).map(\.1) == [.emphasis])
    }

    /// And a loose one is still an ordinary character, which is what makes arithmetic and shell
    /// globs safe to type: a delimiter never opens or closes against whitespace.
    @Test(arguments: [
        "2 * 3 * 4", "SELECT * FROM notes", "chmod +x *.sh", "*.txt and *.md", "a * b * c"
    ])
    func looseAsterisksStyleNothing(text: String) {
        #expect(styled(text).isEmpty)
    }

    /// A path or a glob is characters too, which whitespace alone did not cover: `/usr/*/bin/*x`
    /// drew as `/usr//bin/x` with `/bin/` italic and the asterisks hidden.
    ///
    /// The rule is CommonMark's flanking test — a delimiter facing punctuation inside the pair needs
    /// whitespace or punctuation outside it — so the closing `*` of `/bin/*x` is refused for the `x`
    /// behind it. `2*3*4` and `*.txt/*.md` are *not* here: CommonMark reads those as emphasis, and
    /// agreeing with it is the point.
    @Test(arguments: [
        "/usr/*/bin/*x", "s3://bucket/*/logs/*x", "*.sh *.md and *.txt file",
        "rm -rf /tmp/*/cache/*x"
    ])
    func aFlushAsteriskAgainstAWordCharacterStylesNothing(text: String) {
        #expect(styled(text).isEmpty)
    }

    // MARK: - Escapes

    /// A backslash says what the character after it is not, so a note can hold the markdown it
    /// is talking about. `MarkdownWriting` is what puts them in.
    @Test(arguments: [
        "\\_not italic\\_",
        "\\*\\*not bold\\*\\*",
        "\\~\\~not struck\\~\\~",
        "\\[not a link](https://example.com)"
    ])
    func anEscapedDelimiterStylesNothing(text: String) {
        #expect(styled(text).isEmpty)
    }

    /// The backslash itself is a marker: it has said its piece by the time the note is drawn, so
    /// what is left on screen is the character it was protecting.
    @Test func theBackslashIsAMarkerAndTheCharacterAfterItIsText() {
        #expect(markers("\\*keys\\*") == ["\\", "\\"])
    }

    /// An escaped delimiter cannot close a run either — otherwise `**a \** b**` would end at the
    /// half the note meant literally.
    @Test func anEscapedDelimiterDoesNotCloseARun() {
        #expect(styled("**bold \\** still**").map(\.0) == ["bold \\** still"])
    }

    /// `\\` is an escaped backslash, which leaves the character after it free to mean what it
    /// says. Counting them is what tells the two cases apart.
    @Test func anEscapedBackslashDoesNotEscapeWhatFollowsIt() {
        #expect(styled("\\\\**bold**").map(\.0) == ["bold"])
    }

    /// A backslash in front of anything this parser cannot act on is an ordinary backslash —
    /// these notes are full of paths and regexes, and doubling every one would be its own noise.
    @Test(arguments: ["C:\\Users\\admin", "\\d+ digits", "back\\slash"])
    func aBackslashBeforeAnOrdinaryCharacterIsItselfOrdinary(text: String) {
        #expect(markers(text).isEmpty)
        #expect(styled(text).isEmpty)
    }

    /// Constructs nest, which is the point of spelling italic `_`: `⌘I` inside `**keys**` has a
    /// delimiter of its own to add, so bold-italic is reachable and reversible without any
    /// counting of asterisks. The inner run carries both styles.
    @Test func constructsNest() {
        #expect(styled("**_keys_**").map(\.0) == ["_keys_", "keys"])
        #expect(styled("**_keys_**").map(\.1) == [.strong, .emphasis])
    }

    /// A link's label is still not parsed — `[**a**](b)` reads literally — but the link itself
    /// nests inside an emphasis run like anything else.
    @Test func aLinkNestsButItsLabelIsNotParsed() {
        #expect(styled("**[docs](https://example.com)**").map(\.1) == [.strong, .link])
    }

    // MARK: - Shape

    /// Spans nest rather than overlap: any two are disjoint, or one contains the other and comes
    /// first. That order is what `MarkdownStyling` relies on — it merges each span's font into
    /// what the enclosing span already left behind, so `**_keys_**` ends up bold *and* italic.
    /// Partial overlap would make the result depend on which span happened to be painted last.
    @Test(arguments: [
        "- [ ] **a** and _b_ and [c](d) and ~~e~~",
        "**_keys_**",
        "~~**_a_**~~",
        "**[docs](https://example.com)**"
    ])
    func spansAreDisjointOrNested(text: String) {
        let all = spans(text)

        for (index, outer) in all.enumerated() {
            for inner in all[all.index(after: index)...] {
                let disjoint =
                    NSMaxRange(outer.range) <= inner.range.location
                    || NSMaxRange(inner.range) <= outer.range.location
                let contains =
                    outer.range.location <= inner.range.location
                    && NSMaxRange(inner.range) <= NSMaxRange(outer.range)

                #expect(disjoint || contains)
            }
        }
    }

    @Test func spansStayInsideTheText() {
        let text = "**a**\n- [x] _b_\n[c](d)"

        for span in spans(text) {
            #expect(span.range.location >= 0)
            #expect(NSMaxRange(span.range) <= (text as NSString).length)
        }
    }

    @Test(arguments: ["", "\n", "   ", "plain text", "\n\n\n"])
    func textWithNoMarkdownProducesNoSpans(text: String) {
        #expect(spans(text).isEmpty)
    }

    /// Astral-plane characters make UTF-16 offsets differ from character counts; the parser works
    /// in UTF-16 because that is what the text views use.
    @Test func offsetsAreUTF16() {
        let text = "🔑 **keys**"
        let span = spans(text).first { $0.style == .strong }

        #expect((text as NSString).substring(with: span?.range ?? NSRange()) == "keys")
    }
}
