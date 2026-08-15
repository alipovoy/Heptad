import Testing
import UIKit

@testable import Heptad

/// Whether the note text follows the system text size — the setting an iOS user has already
/// changed before they ever open this app.
///
/// iOS only, and the asymmetry is the design rather than a gap: macOS has no system-wide text
/// size, which is why `⌘+`/`⌘-` and `EditorFontSize` exist there. `PlatformFont.editorBody` says
/// so at the one place either platform decides a size.
///
/// Driven through `UITraitCollection.performAsCurrent` rather than by changing a real setting, so
/// each size below is exact and the test needs nothing of the device it runs on.
@MainActor
struct DynamicTypeTests {

    /// The base every note starts from, which the metrics scale rather than replace.
    private let base = AppConstants.Layout.defaultFontSize

    private func editorPointSize(
        at category: UIContentSizeCategory, plainText: Bool = false
    ) -> CGFloat {
        var size: CGFloat = 0
        UITraitCollection(preferredContentSizeCategory: category).performAsCurrent {
            size = PlatformFont.editorBody(plainText: plainText, size: base).pointSize
        }
        return size
    }

    /// The reason this is safe to ship: at the default category the metrics are the identity, so a
    /// user who has never touched the setting sees the same 16 pt note as before.
    @Test(arguments: [false, true])
    func theDefaultContentSizeLeavesTheNoteExactlyWhereItWas(plainText: Bool) {
        #expect(editorPointSize(at: .large, plainText: plainText) == base)
    }

    /// The defect this closes: a note that stayed 16 pt for someone who had asked the system for
    /// bigger text, with nothing in the app to change it.
    @Test(
        arguments: [
            UIContentSizeCategory.extraLarge, .extraExtraLarge, .extraExtraExtraLarge,
            .accessibilityMedium, .accessibilityExtraExtraExtraLarge
        ])
    func alargerSystemTextSizeDrawsTheNoteLarger(category: UIContentSizeCategory) {
        #expect(editorPointSize(at: category) > base)
    }

    @Test(arguments: [UIContentSizeCategory.small, .extraSmall])
    func aSmallerSystemTextSizeDrawsTheNoteSmaller(category: UIContentSizeCategory) {
        #expect(editorPointSize(at: category) < base)
    }

    /// Monotonic across the whole range, which is what says the base is being *scaled* rather than
    /// swapped for a text style's own fixed size — `.body` at `.large` is 17 pt, so a font that had
    /// been replaced instead of scaled would sit at 17 here and pass the two tests above.
    @Test func theSizeRisesWithEveryStepOfTheSetting() {
        let ladder: [UIContentSizeCategory] = [
            .extraSmall, .small, .medium, .large, .extraLarge, .extraExtraLarge,
            .extraExtraExtraLarge, .accessibilityMedium, .accessibilityLarge,
            .accessibilityExtraLarge, .accessibilityExtraExtraLarge,
            .accessibilityExtraExtraExtraLarge
        ]

        let sizes = ladder.map { editorPointSize(at: $0) }

        #expect(sizes == sizes.sorted(), "\(sizes)")
        #expect(Set(sizes).count > 1, "and the setting moves it at all")
    }

    /// Both modes scale together. A plain-text note is the same prose at the same size in a
    /// monospaced face, so the two disagreeing about how big the note is would show as a jump on
    /// every toggle of the mode.
    @Test(
        arguments: [UIContentSizeCategory.extraSmall, .large, .accessibilityExtraExtraLarge])
    func bothModesScaleTogether(category: UIContentSizeCategory) {
        #expect(
            editorPointSize(at: category, plainText: true)
                == editorPointSize(at: category, plainText: false))
    }

    /// Every other cut of the font is derived from the body font, so scaling it is enough — bold,
    /// italic and their combination all arrive at the scaled size without knowing about any of it.
    @Test func theDerivedCutsComeAlong() {
        UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraLarge)
            .performAsCurrent {
                let body = PlatformFont.editorBody(plainText: false, size: base)

                #expect(body.pointSize > base, "the premise of the three below")
                #expect(body.bolded().pointSize == body.pointSize)
                #expect(body.italicized().pointSize == body.pointSize)
                #expect(body.bolded().italicized().pointSize == body.pointSize)
            }
    }

    /// The zoom stored in defaults stays the base the scaling starts from, rather than being
    /// replaced by it. Nothing on iOS writes that value today, but the appearance is built by
    /// shared code that reads it, so a size other than the default has to still mean something.
    @Test func theStoredSizeIsStillTheBase() {
        let appearance = MarkdownStyling.Appearance(plainText: false, fontSize: 24)

        var scaled: CGFloat = 0
        UITraitCollection(preferredContentSizeCategory: .large).performAsCurrent {
            scaled = appearance.baseFont.pointSize
        }

        #expect(scaled == 24, "at the default category the base is what is drawn")
    }
}
