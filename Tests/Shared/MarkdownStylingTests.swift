import Foundation
import Testing

#if canImport(UIKit)
    import UIKit
#else
    import AppKit
#endif

@testable import Heptad

/// What an editor is allowed to hold, and the range arithmetic that keeps it there.
///
/// `MarkdownStyling.normalize` runs from the text storage's `didProcessEditing` hook on every
/// keystroke, handed the range the edit landed on. It is the fix for #117 in its rich-text shape:
/// a paste can arrive carrying a font, a colour and an alignment, and only the four things with a
/// markdown spelling are allowed to survive it — because those are the only things
/// `MarkdownWriting` can write back to the store.
struct MarkdownStylingTests {

    private let appearance = MarkdownStyling.Appearance(
        plainText: false, fontSize: AppConstants.Layout.defaultFontSize)

    private let plain = MarkdownStyling.Appearance(
        plainText: true, fontSize: AppConstants.Layout.defaultFontSize)

    private func storage(_ text: String) -> NSMutableAttributedString {
        NSMutableAttributedString(string: text)
    }

    private func font(_ storage: NSAttributedString, at location: Int) throws -> PlatformFont {
        try #require(storage.attribute(.font, at: location, effectiveRange: nil) as? PlatformFont)
    }

    // MARK: - What survives

    /// The vocabulary, one trait at a time: what a command can produce, normalize keeps.
    @Test(.bug(id: 124)) func theFormattingWithAMarkdownSpellingSurvives() throws {
        let text = storage("bold italic struck")
        text.addAttribute(
            .font, value: appearance.baseFont.bolded(), range: NSRange(location: 0, length: 4))
        text.addAttribute(
            .font, value: appearance.baseFont.italicized(), range: NSRange(location: 5, length: 6))
        text.addAttribute(
            .strikethroughStyle, value: NSUnderlineStyle.single.rawValue,
            range: NSRange(location: 12, length: 6))

        MarkdownStyling.normalize(appearance, in: text)

        #expect(try font(text, at: 0).isBold)
        #expect(try font(text, at: 5).isItalic)
        #expect(text.attribute(.strikethroughStyle, at: 12, effectiveRange: nil) != nil)
    }

    @Test(.bug(id: 124)) func aLinkKeepsItsDestination() throws {
        let text = storage("docs")
        text.addAttribute(
            .link, value: "https://example.com", range: NSRange(location: 0, length: 4))

        MarkdownStyling.normalize(appearance, in: text)

        #expect(
            text.attribute(.link, at: 0, effectiveRange: nil) as? String == "https://example.com")
        #expect(
            text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? PlatformColor
                == .editorLink)
    }

    // MARK: - What does not

    /// The reported shape of #117: a pasted run arrives 24pt, red and centred. The bold is the
    /// only part of it this app could ever write back out, so it is the only part that stays.
    @Test(.bug(id: 117)) func everythingWithoutAMarkdownSpellingIsTakenBackOff() throws {
        let centred = NSMutableParagraphStyle()
        centred.alignment = .center

        let text = storage("pasted")
        text.setAttributes(
            [
                .font: PlatformFont.boldSystemFont(ofSize: 24),
                .foregroundColor: PlatformColor.red,
                .paragraphStyle: centred,
                .kern: 4
            ], range: NSRange(location: 0, length: 6))

        MarkdownStyling.normalize(appearance, in: text)

        let font = try font(text, at: 0)
        #expect(font.isBold, "The bold is the one thing that has a spelling")
        #expect(font.pointSize == appearance.fontSize, "at the note's own size")
        #expect(
            text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? PlatformColor
                == .adaptiveEditorText)
        #expect(text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) == nil)
        #expect(text.attribute(.kern, at: 0, effectiveRange: nil) == nil)
    }

    /// Plain mode is flat by definition — it shows the source, and source has no formatting.
    @Test func plainModeKeepsNothingAtAll() throws {
        let text = storage("**keys**")
        text.addAttribute(
            .font, value: appearance.baseFont.bolded(), range: NSRange(location: 0, length: 8))

        MarkdownStyling.normalize(plain, in: text)

        #expect(try font(text, at: 0) == plain.baseFont)
    }

    /// A zoom step is a normalize at a new size: every run is rebuilt, weight and slant intact.
    @Test func zoomingRebuildsEveryRunAtTheNewSize() throws {
        let text = storage("bold")
        text.addAttribute(
            .font, value: appearance.baseFont.bolded(), range: NSRange(location: 0, length: 4))

        MarkdownStyling.normalize(
            MarkdownStyling.Appearance(plainText: false, fontSize: 24), in: text)

        #expect(try font(text, at: 0).pointSize == 24)
        #expect(try font(text, at: 0).isBold)
    }

    // MARK: - Ranges that reach past the text

    /// The edited range a storage delegate is handed describes text that may no longer be there:
    /// after a deletion it can start at or past the end of what is left. The clamp in front of
    /// every read is what stands between that and a crash while typing.
    @Test(arguments: [
        NSRange(location: 4, length: 0),  // exactly at the end
        NSRange(location: 4, length: 40),  // starts at the end and runs past it
        NSRange(location: 99, length: 0),  // starts past the end
        NSRange(location: 99, length: 40),  // entirely past the end
        NSRange(location: 0, length: 999)  // starts inside, overruns
    ])
    func aRangeReachingPastTheTextIsClampedToIt(edited: NSRange) {
        let text = storage("keys")

        MarkdownStyling.normalize(appearance, in: text, over: edited)

        // The subject is that the call returns at all: `normalize` writes attributes and never
        // characters, so this comparison cannot fail — an out-of-range read traps, and a trap
        // fails the test. Read it as `#expect(noTrap)`.
        #expect(text.string == "keys", "Normalizing never changes a character")
    }

    @Test func normalizingEmptyStorageDoesNothing() {
        let empty = storage("")

        MarkdownStyling.normalize(appearance, in: empty)
        MarkdownStyling.normalize(appearance, in: empty, over: NSRange(location: 0, length: 0))

        // As above: the absence of a trap is the assertion. Nothing else could change here.
        #expect(empty.length == 0)
    }

    /// Scoped to the range it is given, so an edit on one line leaves the rest of the note alone.
    @Test func normalizingOneRangeLeavesTheRestAlone() {
        let text = storage("one\ntwo")
        text.addAttribute(.kern, value: 4, range: NSRange(location: 0, length: 7))

        MarkdownStyling.normalize(appearance, in: text, over: NSRange(location: 0, length: 3))

        #expect(text.attribute(.kern, at: 0, effectiveRange: nil) == nil)
        #expect(
            text.attribute(.kern, at: 5, effectiveRange: nil) != nil,
            "and the other line as it was")
    }
}
