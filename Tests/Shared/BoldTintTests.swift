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
            plainText: false, fontSize: AppConstants.Layout.defaultFontSize, boldTint: tint)
    }

    private var untinted: MarkdownStyling.Appearance {
        MarkdownStyling.Appearance(
            plainText: false, fontSize: AppConstants.Layout.defaultFontSize)
    }

    private var plain: MarkdownStyling.Appearance {
        MarkdownStyling.Appearance(
            plainText: true, fontSize: AppConstants.Layout.defaultFontSize, boldTint: tint)
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
    private func resolved(_ color: PlatformColor, dark: Bool) -> PlatformColor {
        #if canImport(UIKit)
            return color.resolvedColor(
                with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light))
        #else
            var flattened: NSColor?
            NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
                flattened = color.usingColorSpace(.sRGB)
            }
            return flattened ?? color
        #endif
    }

    /// The paper the tint is read against: `ContentView.backgroundFill` — the note's colour at one
    /// tenth — composited over the window. Computed rather than measured off a rendered view: the
    /// ratio being defended is a property of two colours, not of any layout.
    private func background(forNoteIndex index: Int, dark: Bool) -> PlatformColor {
        let paper: CGFloat = dark ? 0.11 : 1.0
        let note = resolved(PlatformColor(NotePalette.colors[index]), dark: dark)

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        note.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        return PlatformColor(
            red: 0.1 * red + 0.9 * paper, green: 0.1 * green + 0.9 * paper,
            blue: 0.1 * blue + 0.9 * paper, alpha: 1)
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
        let tint = luminance(of: NotePalette.boldTint(forNoteIndex: index).color, dark: dark)
        let paper = luminance(of: background(forNoteIndex: index, dark: dark), dark: dark)
        return (max(tint, paper) + 0.05) / (min(tint, paper) + 0.05)
    }

    private func isTint(_ color: PlatformColor) -> Bool {
        [true, false].allSatisfy {
            resolved(color, dark: $0) == resolved(tint.color, dark: $0)
        }
    }

    // MARK: - The colour itself

    /// Seven notes, seven distinguishable colours. The tint's whole job is to say *which* note
    /// this is, so two palette entries collapsing to one tint would be worse than no tint at all.
    @Test func everyNoteGetsItsOwnTint() {
        for dark in [false, true] {
            let drawn = (0..<AppConstants.noteCount).map {
                resolved(NotePalette.boldTint(forNoteIndex: $0).color, dark: dark)
            }
            #expect(Set(drawn).count == AppConstants.noteCount, "dark: \(dark)")
        }
    }

    /// The index comes from a stored selection by the time it reaches here, the same as every
    /// other read of the palette — so it is clamped rather than trapped on.
    ///
    /// Both doors. `BoldTint`'s memberwise initializer is internal, so the type could be built
    /// out of range without going past the palette function at all, and `color` subscripted a
    /// seven-entry array with whatever it was handed.
    @Test(arguments: [-1, 99])
    func anOutOfRangeNoteIndexClampsRatherThanCrashing(index: Int) {
        let expected = index < 0 ? 0 : AppConstants.noteCount - 1

        #expect(NotePalette.boldTint(forNoteIndex: index) == NotePalette.boldTint(forNoteIndex: expected))
        #expect(BoldTint(noteIndex: index).noteIndex == expected)
        #expect(BoldTint(noteIndex: index).color == BoldTint(noteIndex: expected).color)
    }

    /// Every tint clears WCAG AA for body text against its own note's background, in both
    /// appearances — with headroom, so a palette tweak has somewhere to move before it is a
    /// legibility bug. Bold text would only have needed 3:1.
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
        let bold = text.string.count - 1

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
    @Test func aBoldLinkKeepsTheLinkColour() throws {
        let text = rendered("[**docs**](https://example.com)", appearance)

        #expect(try foreground(text, at: 0) == .editorLink)
        #expect(text.attribute(.link, at: 0, effectiveRange: nil) != nil)
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
    @Test(arguments: ["**bold**", "**_both_**", "rotate **keys** now", "[**docs**](https://e.co)"])
    func theTintNeverReachesTheStore(_ markdown: String) {
        #expect(MarkdownWriting.markdown(from: rendered(markdown, appearance)) == markdown)
    }

    /// `Appearance` is compared on every update pass to decide whether to repaint, and a repaint
    /// is a normalize of the whole buffer. Carrying a live platform colour here would have made
    /// two appearances for the same note unequal and rebuilt every run on every keystroke.
    @Test func twoAppearancesForTheSameNoteAreEqual() {
        func appearance(forNoteIndex index: Int) -> MarkdownStyling.Appearance {
            MarkdownStyling.Appearance(
                plainText: false, fontSize: 16,
                boldTint: NotePalette.boldTint(forNoteIndex: index))
        }

        let built = (0..<AppConstants.noteCount).map(appearance(forNoteIndex:))
        let rebuilt = (0..<AppConstants.noteCount).map(appearance(forNoteIndex:))

        #expect(built == rebuilt, "the same note must not look like a change")
        #expect(Set(built.map(\.boldTint?.noteIndex)).count == AppConstants.noteCount)
    }
}
