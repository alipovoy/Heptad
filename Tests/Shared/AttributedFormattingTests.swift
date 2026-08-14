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
/// applied wherever it is asked for, since every one of them now has a spelling.
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
        #expect(MarkdownWriting.markdown(from: text) == "**bold plain**")

        toggle(.strong, over: NSRange(location: 0, length: 10), in: text)
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

        #expect(MarkdownWriting.markdown(from: text) == "keys")
    }

    @Test(.bug(id: 124)) func takingOneTraitOffLeavesTheOthersOn() {
        let text = storage("keys")
        let all = NSRange(location: 0, length: 4)

        toggle(.strong, over: all, in: text)
        toggle(.emphasis, over: all, in: text)
        toggle(.strong, over: all, in: text)

        #expect(MarkdownWriting.markdown(from: text) == "_keys_")
    }

    // MARK: - What it declines

    /// Nothing, any more. `_` cannot be written against a word character — `key_sto_re` is an
    /// identifier to the parser, not italic — so the command used to refuse mid-word rather than
    /// leave the note in a state the writer would drop. The writer spells that run `*` now, so
    /// ⌘I is an ordinary toggle wherever the caret is, the way ⌘B always was.
    @Test func italicIsAppliedInTheMiddleOfAWord() {
        let text = storage("keystore")

        toggle(.emphasis, over: NSRange(location: 3, length: 3), in: text)

        #expect(MarkdownWriting.markdown(from: text) == "key*sto*re")
    }

    /// And taking it off part of an italic word leaves the rest italic, which is the same rule
    /// seen from the other side: `foo_bar_` has no spelling, `foo*bar*` does.
    @Test func takingItalicOffPartOfAWordLeavesTheRest() {
        let text = storage("_foobar_")

        toggle(.emphasis, over: NSRange(location: 0, length: 3), in: text)

        #expect(MarkdownWriting.markdown(from: text) == "foo*bar*")
    }

    /// Bold never needed the rule: `**` is nobody's identifier.
    @Test func boldIsAppliedInTheMiddleOfAWord() {
        let text = storage("keystore")

        toggle(.strong, over: NSRange(location: 3, length: 3), in: text)

        #expect(MarkdownWriting.markdown(from: text) == "key**sto**re")
    }

    /// The selection is trimmed to its core, so a trailing space is not what gets formatted —
    /// the writer would put it outside the pair anyway.
    @Test func aTrailingSpaceIsNotPartOfTheRun() {
        let text = storage("rotate keys")

        toggle(.strong, over: NSRange(location: 0, length: 7), in: text)

        #expect(MarkdownWriting.markdown(from: text) == "**rotate** keys")
    }

    // MARK: - The caret

    /// With nothing selected the command answers with what typing should continue in, and writes
    /// nothing: a press the user thinks better of leaves no mark on the note.
    @Test func anEmptySelectionArmsTheCaretWithoutTouchingTheText() throws {
        let text = storage("keys")

        let typing = AttributedFormatting.toggle(
            .strong, over: NSRange(location: 4, length: 0), in: text, appearance: appearance)

        #expect(text.string == "keys")
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
