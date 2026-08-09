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

    /// `*` is not a delimiter at all now that italic is `_`, so a bold pair is one construct and
    /// there is no shorter delimiter for it to be mistaken for.
    @Test func boldIsOneConstructRatherThanTwo() {
        #expect(styled("**bold**").map(\.1) == [.strong])
    }

    /// `*` is an ordinary character, which is what makes arithmetic and shell globs safe to type.
    @Test(arguments: ["*italic*", "2 * 3 * 4", "SELECT * FROM notes", "chmod +x *.sh"])
    func asterisksOnTheirOwnStyleNothing(text: String) {
        #expect(styled(text).isEmpty)
    }

    /// A documented limit rather than a bug: there are no escapes, so a note that genuinely
    /// contains delimiters renders them. Pinned so the cost of the choice stays visible.
    @Test func thereAreNoEscapes() {
        #expect(styled("\\_not italic\\_").map(\.0) == ["not italic\\"])
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
