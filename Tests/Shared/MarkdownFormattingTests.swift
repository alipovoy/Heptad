import Foundation
import Testing

@testable import Heptad

/// The rule behind ⌘B, ⌘I and ⌘⇧X, as pure string work. `EditorFormattingTests` drives the same
/// rule through a real text view; this pins the edges that are awkward to reach from there.
struct MarkdownFormattingTests {

    /// Applies the edit the way a text view would, so a case reads as before → after.
    private func toggle(
        _ emphasis: MarkdownFormatting.Emphasis, _ text: String, _ range: NSRange
    ) -> (text: String, selection: NSRange?) {
        let edit = MarkdownFormatting.toggle(emphasis, in: text as NSString, selectedRange: range)
        let applied = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        return (applied, edit.selection)
    }

    @Test(arguments: [
        (MarkdownFormatting.Emphasis.strong, "**keys**"),
        (.emphasis, "_keys_"),
        (.strikethrough, "~~keys~~")
    ])
    func wrappingTheSelection(emphasis: MarkdownFormatting.Emphasis, expected: String) {
        #expect(toggle(emphasis, "keys", NSRange(location: 0, length: 4)).text == expected)
    }

    /// Wrapping leaves the *inner* text selected, which is what lets a second press find its own
    /// delimiters and take them off again. Without it the commands would not be their own inverse.
    @Test func wrappingKeepsTheInnerTextSelected() {
        let result = toggle(.strong, "rotate keys", NSRange(location: 7, length: 4))

        #expect(result.text == "rotate **keys**")
        #expect(result.selection == NSRange(location: 9, length: 4))
    }

    @Test(arguments: MarkdownFormatting.Emphasis.allCases)
    func togglingTwiceIsTheIdentity(emphasis: MarkdownFormatting.Emphasis) throws {
        let first = toggle(emphasis, "rotate keys", NSRange(location: 7, length: 4))
        let selection = try #require(first.selection, "Wrapping must place the selection")

        #expect(toggle(emphasis, first.text, selection).text == "rotate keys")
    }

    /// Selecting the delimiters along with the text is the other way to ask for them off.
    @Test func selectingTheWholeRunUnwrapsIt() {
        let result = toggle(.strong, "**keys**", NSRange(location: 0, length: 8))

        #expect(result.text == "keys")
        #expect(result.selection == NSRange(location: 0, length: 4))
    }

    /// An empty pair is not a run to unwrap — there is nothing between the delimiters — so
    /// selecting one wraps it again rather than collapsing it.
    @Test func anEmptyPairIsWrappedRatherThanUnwrapped() {
        #expect(toggle(.strong, "****", NSRange(location: 0, length: 4)).text == "********")
    }

    /// With nothing selected the caret lands between the halves, so what is typed next is inside.
    @Test func anEmptySelectionOpensAPairAroundTheCaret() {
        let result = toggle(.strong, "rotate ", NSRange(location: 7, length: 0))

        #expect(result.text == "rotate ****")
        #expect(result.selection == NSRange(location: 9, length: 0))
    }

    /// The trap that spelling italic `_` removes. While italic was `*`, a prefix of `**`, ⌘I
    /// inside `**keys**` had to decide whether the asterisk it found was its own or half of the
    /// bold pair — it peeled the pair apart, and once guarded, grew it without shrinking it. Now
    /// there is nothing to decide: ⌘I adds its own delimiter inside the bold one.
    @Test func emphasisInsideBoldNestsRatherThanDisturbingIt() {
        #expect(toggle(.emphasis, "**keys**", NSRange(location: 2, length: 4)).text
            == "**_keys_**")
    }

    /// And back off again, which is what the old spelling could not do.
    @Test func emphasisInsideBoldComesBackOff() {
        #expect(toggle(.emphasis, "**_keys_**", NSRange(location: 3, length: 4)).text
            == "**keys**")
    }

    /// Selecting the whole bold run and pressing ⌘I wraps the run rather than disturbing it.
    @Test func emphasisOverAWholeBoldRunWrapsIt() {
        #expect(toggle(.emphasis, "**keys**", NSRange(location: 0, length: 8)).text
            == "_**keys**_")
    }

    // MARK: - Word boundaries

    /// ⌘I must not mistake an identifier's underscores for its own delimiters. Selecting `SECRET`
    /// in `AWS_SECRET_KEY` and pressing ⌘I found a `_` either side and "unwrapped" them —
    /// silently deleting two characters from the note. The parser never read those underscores as
    /// delimiters, so the command may not either.
    @Test func emphasisDoesNotEatTheUnderscoresInAnIdentifier() {
        let result = toggle(.emphasis, "AWS_SECRET_KEY", NSRange(location: 4, length: 6))

        #expect(result.text == "AWS_SECRET_KEY")
    }

    /// The other half of the same rule: mid-word there is no pair ⌘I could write that its own
    /// parser would read back, so it declines rather than leaving `_key_store` in the note.
    @Test(arguments: [
        NSRange(location: 0, length: 3),  // "key" in "keystore"
        NSRange(location: 3, length: 5),  // "store"
        NSRange(location: 3, length: 0)  // a bare caret mid-word
    ])
    func emphasisDeclinesWhereItCouldNotBeReadBack(selection: NSRange) {
        #expect(toggle(.emphasis, "keystore", selection).text == "keystore")
    }

    /// Bold is unaffected — `**` never turns up inside an identifier, so it needs no such rule.
    @Test func boldStillWrapsInsideAWord() {
        #expect(toggle(.strong, "keystore", NSRange(location: 0, length: 3)).text
            == "**key**store")
    }

    // MARK: - Selections the parser would refuse

    /// `MarkdownSyntax` will not close a delimiter against whitespace, so a selection that takes
    /// in a trailing space used to produce `**keys **` — four literal asterisks, and no command
    /// left that could remove them. The delimiters go around the content, not around the
    /// selection.
    @Test(arguments: [
        NSRange(location: 7, length: 5),  // "keys " — trailing space
        NSRange(location: 6, length: 5),  // " keys" — leading space
        NSRange(location: 6, length: 6)  // " keys " — both
    ])
    func wrappingLeavesSurroundingWhitespaceOutsideTheDelimiters(selection: NSRange) {
        #expect(toggle(.strong, "rotate keys now", selection).text == "rotate **keys** now")
    }

    /// A construct never spans lines, so one pair around a multi-line selection is markdown that
    /// can never be read back. Each line gets its own pair instead.
    @Test func wrappingASelectionAcrossLinesWrapsEachLine() {
        let result = toggle(.strong, "line one\nline two", NSRange(location: 0, length: 17))
        #expect(result.text == "**line one**\n**line two**")
    }

    /// And the direction is decided once for the whole selection, so a second press undoes the
    /// first rather than wrapping the lines a second time.
    @Test func wrappingAcrossLinesIsStillItsOwnInverse() throws {
        let first = toggle(.strong, "line one\nline two", NSRange(location: 0, length: 17))
        let selection = try #require(first.selection)

        #expect(toggle(.strong, first.text, selection).text == "line one\nline two")
    }

    /// Blank lines carry no content to wrap, and the newlines and indentation between lines are
    /// carried over untouched.
    @Test func wrappingAcrossLinesSkipsBlankOnesAndKeepsIndentation() {
        let text = "one\n\n  two"
        #expect(toggle(.strong, text, NSRange(location: 0, length: 10)).text
            == "**one**\n\n  **two**")
    }
}
