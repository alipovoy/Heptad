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
        (.emphasis, "*keys*"),
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

    /// A selection at the very start has no room for a delimiter in front of it, which is where
    /// the "delimiters just outside" check would read past the start of the string.
    @Test func aSelectionAtTheStartIsWrappedWithoutReadingPastTheText() {
        #expect(toggle(.strong, "keys", NSRange(location: 0, length: 4)).text == "**keys**")
    }

    @Test func aSelectionAtTheEndIsWrappedWithoutReadingPastTheText() {
        #expect(
            toggle(.strong, "rotate keys", NSRange(location: 7, length: 4)).text
                == "rotate **keys**")
    }

    /// `*` is a prefix of `**`, so an unwrap that looks only one delimiter out reads the inner
    /// half of a bold pair as its own emphasis run — ⌘I inside `**keys**` peeled one asterisk off
    /// each side and quietly turned the bold into italic. Each command owns its own delimiter.
    @Test func emphasisDoesNotPeelABoldPairApart() {
        #expect(toggle(.emphasis, "**keys**", NSRange(location: 2, length: 4)).text
            == "***keys***")
    }

    /// The same trap from the other side: selecting the whole bold run and pressing ⌘I must not
    /// unwrap it either.
    @Test func emphasisOverAWholeBoldRunDoesNotUnwrapIt() {
        #expect(toggle(.emphasis, "**keys**", NSRange(location: 0, length: 8)).text
            == "***keys***")
    }
}
