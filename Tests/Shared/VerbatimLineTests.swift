import Foundation
import Testing

@testable import Heptad

/// The writer's short circuit: the lines it may hand back untouched, and the ones it may not.
///
/// `verbatimLine` claims a line only when every rung of the ladder and the unconditional fallback
/// would have produced the same bytes anyway. What it must never do is claim a line the ladder
/// would have spelled differently — so each case below pins the answer, not just the speed.
struct VerbatimLineTests {

    private let appearance = MarkdownStyling.Appearance(
        plainText: false, fontSize: AppConstants.Layout.defaultFontSize)

    private func rendered(_ markdown: String) -> NSMutableAttributedString {
        NSMutableAttributedString(
            attributedString: RichTextRendering.attributed(from: markdown, appearance: appearance))
    }

    private func verbatim(_ markdown: String) -> String? {
        let text = rendered(markdown)
        return MarkdownWriting.verbatimLine(
            NSRange(location: 0, length: text.length), of: text,
            in: text.string as NSString)
    }

    /// Italic applied to a run flush against word characters — what `⌘I` over part of a word
    /// leaves, and a shape no markdown source can express.
    private func italicised(_ text: String, over word: String) -> NSMutableAttributedString {
        let storage = NSMutableAttributedString(
            string: text, attributes: MarkdownStyling.baseAttributes(appearance))
        _ = AttributedFormatting.toggle(
            .emphasis, over: (text as NSString).range(of: word), in: storage,
            appearance: appearance)
        return storage
    }

    // MARK: - Lines it may claim

    @Test func proseWithNothingToSpellIsHandedBackAsItself() {
        #expect(verbatim("just ordinary words here") == "just ordinary words here")
    }

    @Test func aListMarkerIsNotSyntaxTheWriterHasToDefendAgainst() {
        #expect(verbatim("- milk") == "- milk")
        #expect(verbatim("1. first") == "1. first")
    }

    /// `#` and `` ` `` are not escapable, so the ladder had no spelling for them either: it wrote
    /// the characters and so does this.
    @Test func markupTheWriterNeverEscapedIsStillWrittenAsItself() {
        #expect(verbatim("# heading") == "# heading")
        #expect(verbatim("`code`") == "`code`")
        #expect(verbatim("> quote") == "> quote")
    }

    @Test func nonLatinTextAndEmojiAreClaimedWhole() {
        #expect(verbatim("多字节文本") == "多字节文本")
        #expect(verbatim("a 👍 b") == "a 👍 b")
    }

    // MARK: - Lines it must refuse

    @Test func anEscapableCharacterGoesToTheLadder() {
        for line in ["a*b", "a_b", "a~b", "a[b", "a]b", "a(b", "a)b", "a\\b"] {
            #expect(verbatim(line) == nil, "\(line) needs the ladder's escaping")
        }
    }

    @Test func anEmphasisedRunGoesToTheLadder() {
        let text = italicised("the hardware ships\n", over: "hard")
        #expect(
            MarkdownWriting.verbatimLine(
                NSRange(location: 0, length: text.length), of: text,
                in: text.string as NSString) == nil)
    }

    @Test func aLinkGoesToTheLadder() {
        #expect(verbatim("[docs](https://example.com)") == nil)
    }

    // MARK: - What the short circuit must not change

    /// The case the ladder exists for: `_` cannot close against `w`, so the line has to retreat to
    /// `*`. Pinned here because a short circuit that claimed this line would lose the trait.
    @Test func italicFlushAgainstAWordStillRetreatsToTheOtherSpelling() {
        #expect(
            MarkdownWriting.markdown(from: italicised("the hardware ships", over: "hard"))
                == "the *hard*ware ships")
    }

    @Test func aNoteMixingClaimedAndLadderedLinesWritesBothCorrectly() {
        let note = rendered("plain line\n**bold** line\nanother plain one\n[a](u)")
        #expect(
            MarkdownWriting.markdown(from: note)
                == "plain line\n**bold** line\nanother plain one\n[a](u)")
    }
}
