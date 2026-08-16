import Foundation
import Testing

#if canImport(UIKit)
    import UIKit
#else
    import AppKit
#endif

@testable import Heptad

/// The toggle itself, without a text view around it.
///
/// `EditorFormattingTests` drives these through ⌘B and the real editor; this pins the decisions
/// the rule makes on its own — which direction a mixed selection goes, and that every trait is
/// applied wherever it is asked for.
struct AttributedFormattingTests {

    private let appearance = MarkdownStyling.Appearance(
        plainText: false, fontSize: AppConstants.Layout.defaultFontSize)

    private func storage(_ markdown: String) -> NSMutableAttributedString {
        NSMutableAttributedString(
            attributedString: RichTextRendering.attributed(from: markdown, appearance: appearance))
    }

    private func toggle(
        _ emphasis: Emphasis, over range: NSRange, in storage: NSMutableAttributedString
    ) {
        AttributedFormatting.toggle(
            emphasis, over: range, in: storage, appearance: appearance)
    }

    // MARK: - Direction

    /// Off only when *every* character already carries it, so a partly-bold selection goes fully
    /// bold on the first press rather than inverting run by run and leaving a stripe.
    @Test func aPartlyFormattedSelectionGoesFullyFormattedFirst() {
        let text = storage("**bold** plain")

        toggle(.strong, over: NSRange(location: 0, length: 10), in: text)
        #expect(text.carrying(.strong) == "##########", "all of it, not the stripe")
        #expect(MarkdownWriting.markdown(from: text) == "**bold plain**")

        toggle(.strong, over: NSRange(location: 0, length: 10), in: text)
        #expect(text.carrying(.strong) == "..........")
        #expect(MarkdownWriting.markdown(from: text) == "bold plain")
    }

    /// Any order, any nesting: the reported bug in #124 was that this did not hold.
    @Test(.bug(id: 124), arguments: [
        [Emphasis.strong, .emphasis, .strikethrough],
        [.strikethrough, .strong, .emphasis],
        [.emphasis, .strikethrough, .strong]
    ])
    func applyingEverythingThenTakingItOffLeavesTheTextAsItWas(order: [Emphasis]) {
        let text = storage("keys")
        let all = NSRange(location: 0, length: 4)

        for emphasis in order { toggle(emphasis, over: all, in: text) }
        for emphasis in order.reversed() { toggle(emphasis, over: all, in: text) }

        #expect(
            Emphasis.allCases.allSatisfy { text.carrying($0) == "...." },
            "no trait left on any character")
        #expect(MarkdownWriting.markdown(from: text) == "keys")
    }

    @Test(.bug(id: 124)) func takingOneTraitOffLeavesTheOthersOn() {
        let text = storage("keys")
        let all = NSRange(location: 0, length: 4)

        toggle(.strong, over: all, in: text)
        toggle(.emphasis, over: all, in: text)
        toggle(.strong, over: all, in: text)

        #expect(text.carrying(.emphasis) == "####")
        #expect(text.carrying(.strong) == "....")
        #expect(MarkdownWriting.markdown(from: text) == "_keys_")
    }

    // MARK: - What it declines

    /// Nothing, any more. `_` against a word character is an identifier to the parser, not italic,
    /// so the writer spells that run `*` and ⌘I is an ordinary toggle wherever the caret is.
    @Test func italicIsAppliedInTheMiddleOfAWord() {
        let text = storage("keystore")

        toggle(.emphasis, over: NSRange(location: 3, length: 3), in: text)

        #expect(text.carrying(.emphasis) == "...###..")
        #expect(MarkdownWriting.markdown(from: text) == "key*sto*re")
    }

    /// And taking it off part of an italic word leaves the rest italic: `foo_bar_` has no
    /// spelling, `foo*bar*` does.
    @Test func takingItalicOffPartOfAWordLeavesTheRest() {
        let text = storage("_foobar_")

        toggle(.emphasis, over: NSRange(location: 0, length: 3), in: text)

        #expect(text.carrying(.emphasis) == "...###")
        #expect(MarkdownWriting.markdown(from: text) == "foo*bar*")
    }

    /// Bold never needed the rule: `**` is nobody's identifier.
    @Test func boldIsAppliedInTheMiddleOfAWord() {
        let text = storage("keystore")

        toggle(.strong, over: NSRange(location: 3, length: 3), in: text)

        #expect(text.carrying(.strong) == "...###..")
        #expect(MarkdownWriting.markdown(from: text) == "key**sto**re")
    }

    /// The selection is trimmed to its core, so a trailing space is not what gets formatted.
    ///
    /// Asserted on the buffer, because the store cannot see it: the writer puts the space outside
    /// the pair either way, so `**rotate** keys` is written even with the trim dropped.
    @Test func aTrailingSpaceIsNotPartOfTheRun() {
        let text = storage("rotate keys")

        toggle(.strong, over: NSRange(location: 0, length: 7), in: text)

        #expect(text.carrying(.strong) == "######.....", "the space is not in the run")
        #expect(MarkdownWriting.markdown(from: text) == "**rotate** keys")
    }

    // MARK: - List markers

    /// A whole list line can be formatted without the line stopping being a list line.
    ///
    /// The pair goes around the content, never around the marker: `**- [ ] task**` round-trips
    /// character for character, so the writer's check accepts it, but
    /// `ListContinuation.markerLength` no longer reads it — Return stops continuing the list and
    /// `⌘⇧U` finds no checkbox. The bold on the marker itself is dropped instead.
    @Test(arguments: ["- [ ] task", "- item", "* item", "1. item", "  - indented"])
    func formattingAWholeListLineLeavesItsMarkerReadable(line: String) throws {
        let text = storage(line)

        toggle(.strong, over: NSRange(location: 0, length: text.length), in: text)
        let written = MarkdownWriting.markdown(from: text)

        #expect(ListContinuation.markerLength(on: written) != nil, "\(written)")
        #expect(written.hasSuffix("**"), "\(written) — and the content is still bold")
    }

    // MARK: - The caret

    /// With nothing selected the command answers with what typing should continue in, and writes
    /// nothing: a press the user thinks better of leaves no mark on the note.
    @Test func anEmptySelectionArmsTheCaretWithoutTouchingTheText() throws {
        let text = storage("keys")

        let typing = AttributedFormatting.toggle(
            .strong, over: NSRange(location: 4, length: 0), in: text, appearance: appearance)

        #expect(text.string == "keys")
        #expect(text.carrying(.strong) == "....", "nothing was written to the buffer either")
        #expect(MarkdownWriting.markdown(from: text) == "keys")
        let font = try #require(typing[.font] as? PlatformFont)
        #expect(font.isBold)
    }

    /// And in an empty note, where there is no run to read the caret's state off at all.
    @Test func anEmptyNoteArmsTheCaretFromTheBaseAttributes() throws {
        let text = storage("")

        let typing = AttributedFormatting.toggle(
            .strong, over: NSRange(location: 0, length: 0), in: text, appearance: appearance)

        let font = try #require(typing[.font] as? PlatformFont)
        #expect(font.isBold)
    }
}
