import Foundation
import Testing

@testable import Heptad

/// The parser that decides what a note looks like: which characters are markdown and which are
/// just characters.
///
/// Worth pinning closely because it is the app's whole formatting vocabulary. Anything it
/// recognises, a command can produce and remove; anything it does not is text. The deliberate
/// limits — no nesting, no spanning lines, no escapes — are tested as limits rather than left to
/// be discovered as bugs.
struct MarkdownSyntaxTests {

    private func spans(_ text: String) -> [MarkdownSyntax.Span] {
        MarkdownSyntax.spans(in: text as NSString)
    }

    /// The styled ranges, as the substrings they cover — the readable form of an assertion that
    /// would otherwise be a list of offsets.
    private func styled(_ text: String) -> [(String, MarkdownSyntax.Style)] {
        spans(text)
            .filter { $0.style != .marker }
            .map { ((text as NSString).substring(with: $0.range), $0.style) }
    }

    private func markers(_ text: String) -> [String] {
        spans(text)
            .filter { $0.style == .marker }
            .map { (text as NSString).substring(with: $0.range) }
    }

    // MARK: - The vocabulary

    @Test(arguments: [
        ("**bold**", "bold", MarkdownSyntax.Style.strong),
        ("*italic*", "italic", .emphasis),
        ("~~struck~~", "struck", .strikethrough)
    ])
    func delimitedRunsAreStyled(text: String, content: String, style: MarkdownSyntax.Style) {
        #expect(styled(text).map(\.0) == [content])
        #expect(styled(text).map(\.1) == [style])
    }

    /// The delimiters are spans of their own, drawn dimmed. They stay in the buffer — the note is
    /// its source — so the caret can move through them.
    @Test func delimitersAreReportedAsMarkers() {
        #expect(markers("**bold**") == ["**", "**"])
    }

    @Test func linksStyleTheirLabelAndMarkTheRest() {
        #expect(styled("[docs](https://example.com)").map(\.0) == ["docs"])
        #expect(styled("[docs](https://example.com)").map(\.1) == [.link])
        #expect(markers("[docs](https://example.com)") == ["[", "](https://example.com)"])
    }

    /// The list grammar comes from `ListContinuation`, so what Return continues and what the
    /// editor dims are the same set by construction.
    @Test(arguments: ["- ", "* ", "1. ", "- [ ] ", "- [x] ", "  - "])
    func listMarkersAreMarked(marker: String) {
        #expect(markers(marker + "item").first == marker)
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

    @Test(arguments: ["**unclosed", "*also unclosed", "[label](no-paren", "[]()", "****"])
    func incompleteConstructsStyleNothing(text: String) {
        #expect(styled(text).isEmpty)
    }

    /// Constructs never span lines, so a stray delimiter spoils at most its own line.
    @Test func aDelimiterDoesNotCloseOnTheNextLine() {
        #expect(styled("**start\nend**").isEmpty)
    }

    @Test func eachLineIsParsedOnItsOwn() {
        #expect(styled("**one**\nplain\n*two*").map(\.0) == ["one", "two"])
    }

    /// `**` is claimed by the longer delimiter, never split into two empty emphasis runs.
    @Test func boldIsNotReadAsTwoEmphasisRuns() {
        #expect(styled("**bold**").map(\.1) == [.strong])
    }

    /// A documented limit rather than a bug: there are no escapes, so a note that genuinely
    /// contains delimiters renders them. Pinned so the cost of the choice stays visible.
    @Test func thereAreNoEscapes() {
        #expect(styled("\\*not italic\\*").map(\.0) == ["not italic\\"])
    }

    /// Another documented limit: constructs do not nest, and the outer one wins.
    @Test func constructsDoNotNest() {
        #expect(styled("**[docs](https://example.com)**").map(\.1) == [.strong])
    }

    // MARK: - Shape

    @Test func spansNeverOverlap() {
        let text = "- [ ] **a** and *b* and [c](d) and ~~e~~"
        let ordered = spans(text).sorted { $0.range.location < $1.range.location }

        for (previous, next) in zip(ordered, ordered.dropFirst()) {
            #expect(NSMaxRange(previous.range) <= next.range.location)
        }
    }

    @Test func spansStayInsideTheText() {
        let text = "**a**\n- [x] *b*\n[c](d)"

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
