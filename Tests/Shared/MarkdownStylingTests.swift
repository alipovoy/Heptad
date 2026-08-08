import Foundation
import Testing

@testable import Heptad

/// The repaint's range arithmetic.
///
/// `MarkdownStyling.apply(_:to:over:)` runs from the text storage's `didProcessEditing` hook on
/// every keystroke, handed the range the edit landed on. After a deletion that range describes
/// text that is no longer there, so it can start at or past the end of what is left. The clamp in
/// front of `lineRange(for:)` is what stands between that and an out-of-range `NSRange` — a crash
/// while typing, not a wrong colour.
///
/// None of this is reachable from the editor suites: they only ever repaint ranges still inside
/// the buffer, so the clamp is exercised there but never actually put under pressure.
struct MarkdownStylingTests {

    private let appearance = MarkdownStyling.Appearance(
        plainText: false, fontSize: AppConstants.Layout.defaultFontSize)

    private func storage(_ text: String) -> NSMutableAttributedString {
        NSMutableAttributedString(string: text)
    }

    /// The same text, fully repainted — what every clamped repaint below has to match.
    private func fullyRepainted(_ text: String) -> NSMutableAttributedString {
        let storage = storage(text)
        MarkdownStyling.apply(appearance, to: storage)
        return storage
    }

    // MARK: - Nothing to paint

    /// Both entry points guard on an empty buffer, which is the state a cleared note is in.
    @Test func repaintingEmptyStorageDoesNothing() {
        let empty = storage("")

        MarkdownStyling.apply(appearance, to: empty)
        MarkdownStyling.apply(appearance, to: empty, over: NSRange(location: 0, length: 0))

        #expect(empty.length == 0)
    }

    /// A zero-length range still repaints the line the caret sits on — `lineRange(for:)` of an
    /// empty range is the whole line — which is what makes typing a delimiter restyle its line
    /// rather than nothing at all.
    @Test func aZeroLengthRangeStillRepaintsItsLine() throws {
        let text = storage("**keys**")

        MarkdownStyling.apply(appearance, to: text, over: NSRange(location: 4, length: 0))

        let painted = try #require(
            text.attribute(.font, at: 2, effectiveRange: nil) as? PlatformFont)
        #expect(painted != appearance.baseFont, "The line the caret is on is styled")
    }

    // MARK: - Ranges that reach past the text

    /// Every one of these clamps onto the single line the text has, so the result must be
    /// indistinguishable from repainting the whole thing. Asserting that rather than merely "it
    /// did not crash" is what makes the cases capable of failing for a wrong clamp as well as a
    /// fatal one.
    @Test(arguments: [
        NSRange(location: 8, length: 0),  // exactly at the end
        NSRange(location: 8, length: 40),  // starts at the end and runs past it
        NSRange(location: 99, length: 0),  // starts past the end
        NSRange(location: 99, length: 40),  // entirely past the end
        NSRange(location: 0, length: 999)  // starts inside, overruns
    ])
    func aRangeReachingPastTheTextIsClampedToIt(edited: NSRange) {
        let text = storage("**keys**")

        MarkdownStyling.apply(appearance, to: text, over: edited)

        #expect(text.string == "**keys**", "A repaint never changes a character")
        #expect(text.isEqual(to: fullyRepainted("**keys**")), "and lands where a full one would")
    }

    /// The case the clamp exists for, in the shape the editor produces it: characters are deleted
    /// from the end and the storage delegate is handed the range the edit *occupied*, which no
    /// longer fits the text that is left.
    @Test func repaintingAfterADeletionAtTheEndIsHarmless() {
        let text = storage("**keys** and more")
        MarkdownStyling.apply(appearance, to: text)

        let deleted = NSRange(location: 8, length: 9)
        text.replaceCharacters(in: deleted, with: "")

        // The range as it stood before the delete — now past the end of what remains.
        MarkdownStyling.apply(appearance, to: text, over: deleted)

        #expect(text.string == "**keys**")
        #expect(text.isEqual(to: fullyRepainted("**keys**")))
    }

    /// Plain mode takes the early return before any span is drawn, and has to survive the same
    /// out-of-range ranges on the way to it.
    @Test func aPlainAppearanceClampsTheSameWay() {
        let plain = MarkdownStyling.Appearance(
            plainText: true, fontSize: AppConstants.Layout.defaultFontSize)
        let text = storage("**keys**")

        MarkdownStyling.apply(plain, to: text, over: NSRange(location: 99, length: 40))

        let expected = storage("**keys**")
        MarkdownStyling.apply(plain, to: expected)
        #expect(text.isEqual(to: expected))
    }

    /// A repaint scoped to one line leaves the other lines exactly as they were, which is the
    /// property the line-scoped optimisation rests on.
    @Test func repaintingOneLineLeavesTheOthersAlone() {
        let text = fullyRepainted("**one**\nplain\n_three_")
        let before = NSAttributedString(attributedString: text)

        // The middle line, which holds no markdown and so has nothing to redraw.
        MarkdownStyling.apply(appearance, to: text, over: NSRange(location: 9, length: 5))

        #expect(text.isEqual(to: before))
    }
}
