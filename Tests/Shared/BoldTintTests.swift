import Foundation
import Testing

#if canImport(UIKit)
    import UIKit
#else
    import AppKit
#endif

@testable import Heptad

/// Bold text is drawn in the note's own colour, in formatted mode only.
///
/// Formatted mode dropped the delimiters (#124), so there is nothing on screen that says a run is
/// bold except the weight — and a weight is hard to see in one word. The tint gives it a second
/// signal, and ties the note's text to the colour the rest of the window is already wearing.
/// It is paint and nothing more: `MarkdownWriting` reads traits, so none of it reaches the store.
struct BoldTintTests {

    private let tint = NotePalette.boldTint(forNoteIndex: 0)

    private var appearance: MarkdownStyling.Appearance {
        MarkdownStyling.Appearance(
            plainText: false, fontSize: AppConstants.Layout.defaultFontSize, tintedNoteIndex: 0)
    }

    private var untinted: MarkdownStyling.Appearance {
        MarkdownStyling.Appearance(
            plainText: false, fontSize: AppConstants.Layout.defaultFontSize)
    }

    private var plain: MarkdownStyling.Appearance {
        MarkdownStyling.Appearance(
            plainText: true, fontSize: AppConstants.Layout.defaultFontSize, tintedNoteIndex: 0)
    }

    private func rendered(
        _ markdown: String, _ appearance: MarkdownStyling.Appearance
    ) -> NSMutableAttributedString {
        NSMutableAttributedString(
            attributedString: RichTextRendering.attributed(from: markdown, appearance: appearance))
    }

    private func foreground(
        _ text: NSAttributedString, at location: Int
    ) throws -> PlatformColor {
        try #require(
            text.attribute(.foregroundColor, at: location, effectiveRange: nil) as? PlatformColor)
    }

    // MARK: - Resolving

    /// A dynamic colour flattened against one appearance.
    ///
    /// Two dynamic platform colours are never `==` to each other even when built from identical
    /// inputs, so every comparison below is made on resolved values. It is also the only way to
    /// ask what the tint actually *looks* like, which is the half of this feature that matters.
    ///
    /// `PlatformColor.resolved(dark:)` is the app's own — this used to fork on the platform itself,
    /// in the same shape `NotePalette` did, so the two could have drifted while both looked right.
    private func resolved(_ color: PlatformColor, dark: Bool) -> PlatformColor {
        color.resolved(dark: dark) ?? color
    }

    /// The paper the tint is read against: `ContentView.backgroundFill` — the note's colour at
    /// `Layout.noteTintOpacity` — composited over the window. Computed rather than measured off a
    /// rendered view: the ratio being defended is a property of two colours, not of any layout.
    ///
    /// The opacity is read from the app rather than copied here, so raising the wash cannot leave
    /// this suite passing against a background the app no longer paints.
    private func background(forNoteIndex index: Int, dark: Bool) -> PlatformColor {
        let wash = CGFloat(AppConstants.Layout.noteTintOpacity)
        let note = resolved(PlatformColor(NotePalette.colors[index]), dark: dark)
        let paper = self.paper(dark: dark)

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        note.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        return PlatformColor(
            red: wash * red + (1 - wash) * paper, green: wash * green + (1 - wash) * paper,
            blue: wash * blue + (1 - wash) * paper, alpha: 1)
    }

    /// What is behind the note's wash, per platform. `Tests/Shared` compiles into both targets, and
    /// a single literal here was asserting against a background one of them does not have: iOS's
    /// dark paper is black, not the panel's 0.11.
    private func paper(dark: Bool) -> CGFloat {
        #if canImport(UIKit)
            var white: CGFloat = 0
            var alpha: CGFloat = 0
            resolved(.systemBackground, dark: dark).getWhite(&white, alpha: &alpha)
            return white
        #else
            // The panel is a vibrant material, so there is no colour to ask for. Sampled at
            // 0.1176 in dark appearance; 0.11 is the conservative reading of that, and light is
            // white behind the window's own translucency.
            return dark ? 0.11 : 1.0
        #endif
    }

    /// WCAG relative luminance, and the ratio between two of them.
    private func luminance(of color: PlatformColor, dark: Bool) -> CGFloat {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        resolved(color, dark: dark).getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        func linear(_ channel: CGFloat) -> CGFloat {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    private func contrast(forNoteIndex index: Int, dark: Bool) -> CGFloat {
        let tint = luminance(of: NotePalette.boldTint(forNoteIndex: index), dark: dark)
        let paper = luminance(of: background(forNoteIndex: index, dark: dark), dark: dark)
        return (max(tint, paper) + 0.05) / (min(tint, paper) + 0.05)
    }

    private func isTint(_ color: PlatformColor) -> Bool {
        [true, false].allSatisfy {
            resolved(color, dark: $0) == resolved(tint, dark: $0)
        }
    }

    // MARK: - The colour itself

    /// Seven notes, seven *distinguishable* colours — which is what the tint is for, and is not
    /// what `Set(...).count == 7` was checking: two tints a thousandth apart are different values
    /// and the same colour to the eye. Asserted as a distance instead, with the closest pair
    /// (cyan/blue, measured at 0.103 in RGB) just clearing it.
    @Test func everyNoteGetsItsOwnTint() {
        for dark in [false, true] {
            let drawn = (0..<AppConstants.noteCount).map {
                components(of: NotePalette.boldTint(forNoteIndex: $0), dark: dark)
            }

            for first in drawn.indices {
                for second in drawn.indices.dropFirst(first + 1) {
                    let apart = distance(drawn[first], drawn[second])
                    #expect(
                        apart >= 0.1,
                        "notes \(first) and \(second) are \(apart) apart, dark: \(dark)")
                }
            }
        }
    }

    /// A colour's sRGB components, flattened against one appearance.
    private func components(of color: PlatformColor, dark: Bool) -> [CGFloat] {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        resolved(color, dark: dark).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return [red, green, blue]
    }

    private func distance(_ one: [CGFloat], _ other: [CGFloat]) -> CGFloat {
        zip(one, other).reduce(0) { total, pair in total + (pair.0 - pair.1) * (pair.0 - pair.1) }
            .squareRoot()
    }

    /// The index comes from a stored selection by the time it reaches here, the same as every
    /// other read of the palette — so it is clamped rather than trapped on.
    ///
    /// One door now. This used to be reachable past the clamp through `BoldTint`'s internal
    /// memberwise initializer, which subscripted the seven-entry table with whatever it was
    /// handed; the type is gone and the palette function is the only way in.
    @Test(arguments: [-1, 99])
    func anOutOfRangeNoteIndexClampsRatherThanCrashing(index: Int) {
        let expected = index < 0 ? 0 : AppConstants.noteCount - 1

        #expect(
            NotePalette.boldTint(forNoteIndex: index)
                == NotePalette.boldTint(forNoteIndex: expected))
    }

    /// Every tint clears WCAG AA for body text against its own note's background, in both
    /// appearances. Bold text would only have needed 3:1, so 4.5 is the deliberate margin — but it
    /// is not much of one: green in light appearance measures 4.74:1, which is the pair to look at
    /// first if a palette change ever turns this red.
    @Test func everyTintClearsAAAgainstItsOwnNote() {
        for index in 0..<AppConstants.noteCount {
            for dark in [false, true] {
                let ratio = contrast(forNoteIndex: index, dark: dark)
                #expect(
                    ratio >= 4.5,
                    "note \(index) in \(dark ? "dark" : "light") reads at \(ratio):1")
            }
        }
    }

    // MARK: - Where it lands

    @Test func boldIsDrawnInTheNotesColour() throws {
        let text = rendered("plain **bold**", appearance)

        #expect(try foreground(text, at: 0) == .adaptiveEditorText)
        #expect(isTint(try foreground(text, at: 6)))
    }

    /// The trait is what is being marked, not the delimiter pair — so anything carrying bold is
    /// tinted, however it got there.
    @Test(arguments: ["**_bold italic_**", "~~**struck**~~", "- **item**"])
    func everyRunCarryingBoldIsTinted(_ markdown: String) throws {
        let text = rendered(markdown, appearance)
        // `length`, not `string.count`: the attribute index is UTF-16, and the two agree only
        // while every argument stays ASCII.
        let bold = text.length - 1

        #expect(try #require(text.attribute(.font, at: bold, effectiveRange: nil) as? PlatformFont)
            .isBold)
        #expect(isTint(try foreground(text, at: bold)))
    }

    @Test func italicAndStrikethroughAreNotTinted() throws {
        let text = rendered("_italic_ ~~struck~~", appearance)

        #expect(try foreground(text, at: 0) == .adaptiveEditorText)
        #expect(try foreground(text, at: 10) == .adaptiveEditorText)
    }

    /// A link's colour is the only run colour that already meant something, and it wins. A bold
    /// link that stopped looking like a link would trade one signal for another.
    ///
    /// Spelled with the pair *around* the link, which is the only spelling this app reads as a bold
    /// link — a label is not parsed, so `[**docs**](url)` renders the asterisks as characters in
    /// the base font. That was the previous input here, and it meant the test never reached the
    /// bold branch it was named for: deleting the link check outright left it green.
    @Test func aBoldLinkKeepsTheLinkColour() throws {
        let text = rendered("**[docs](https://example.com)**", appearance)

        #expect(text.string == "docs", "a bold link, not four literal asterisks")
        #expect(try #require(text.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont)
            .isBold)
        #expect(text.attribute(.link, at: 0, effectiveRange: nil) != nil)
        #expect(try foreground(text, at: 0) == .editorLink, "and the link colour wins over the tint")
    }

    /// Plain mode shows the source, `**` and all, in one font and one colour. The tint is the
    /// formatted mode's way of saying what the delimiters say here.
    @Test func plainModeTintsNothing() throws {
        let text = rendered("**bold**", plain)

        for location in 0..<text.length {
            #expect(try foreground(text, at: location) == .adaptiveEditorText)
        }
    }

    /// An appearance with no note colour in hand — `MarkdownWriting.reading`, and the tests that
    /// only ask about traits — leaves bold in the body-text colour.
    @Test func withoutATintBoldStaysBodyText() throws {
        let text = rendered("**bold**", untinted)

        #expect(try foreground(text, at: 0) == .adaptiveEditorText)
    }

    // MARK: - Keeping it applied

    /// A paste arrives with a colour of its own; normalize takes it off, and puts the tint on
    /// whatever came in bold.
    @Test func normalizeRepaintsAPastedBoldRun() throws {
        let text = NSMutableAttributedString(
            string: "pasted",
            attributes: [
                .font: PlatformFont.boldSystemFont(ofSize: 24),
                .foregroundColor: PlatformColor.red
            ])

        MarkdownStyling.normalize(appearance, in: text)

        #expect(isTint(try foreground(text, at: 0)))
    }

    /// `⌘B` writes attributes rather than characters, so the storage delegate that normalizes
    /// every other edit never sees it — the toggle has to paint the tint on and off itself.
    @Test func togglingBoldPutsTheTintOnAndTakesItOff() throws {
        let text = rendered("word", appearance)
        let whole = NSRange(location: 0, length: 4)

        AttributedFormatting.toggle(.strong, over: whole, in: text, appearance: appearance)
        #expect(isTint(try foreground(text, at: 0)))

        AttributedFormatting.toggle(.strong, over: whole, in: text, appearance: appearance)
        #expect(try foreground(text, at: 0) == .adaptiveEditorText)
    }

    /// The caret carries the tint out of a `⌘B` with nothing selected, so the first character
    /// typed is already the note's colour rather than turning it on the second.
    @Test func theCaretTakesTheTintWithIt() throws {
        let text = rendered("", appearance)
        let typing = AttributedFormatting.toggle(
            .strong, over: NSRange(location: 0, length: 0), in: text, appearance: appearance)

        #expect(isTint(try #require(typing[.foregroundColor] as? PlatformColor)))
    }

    // MARK: - What it must not touch

    /// The tint is paint. A note is stored as markdown either way, and the writer reads traits.
    ///
    /// One argument: the other three were round-trip arguments, and `RichTextRoundTripTests` owns
    /// that property over 22 of them. What is this suite's to say is that a *tinted* buffer writes
    /// the same markdown an untinted one does.
    @Test func theTintNeverReachesTheStore() {
        let markdown = "rotate **keys** now"

        #expect(MarkdownWriting.markdown(from: rendered(markdown, appearance)) == markdown)
        #expect(
            MarkdownWriting.markdown(from: rendered(markdown, untinted)) == markdown,
            "tinted or not, the same store")
    }

    /// `Appearance` is compared on every update pass to decide whether to repaint. Carrying a live
    /// platform colour here would have made two appearances for the same note unequal and rebuilt
    /// every run on every keystroke; it carries the note's index, which compares by value.
    @Test func twoAppearancesForTheSameNoteAreEqual() {
        func appearance(forNoteIndex index: Int) -> MarkdownStyling.Appearance {
            MarkdownStyling.Appearance(plainText: false, fontSize: 16, tintedNoteIndex: index)
        }

        let built = (0..<AppConstants.noteCount).map(appearance(forNoteIndex:))
        let rebuilt = (0..<AppConstants.noteCount).map(appearance(forNoteIndex:))

        #expect(built == rebuilt, "the same note must not look like a change")
        #expect(
            appearance(forNoteIndex: 0) != appearance(forNoteIndex: 1),
            "and two notes must, or the comparison would skip the repaint that changes the tint")
    }
}
