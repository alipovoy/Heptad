import Testing
import UIKit

@testable import Heptad

/// Whether the note text follows the system text size. iOS only: macOS has no system-wide text
/// size, which is why `⌘+`/`⌘-` and `EditorFontSize` exist there instead.
///
/// Driven through `UITraitCollection.performAsCurrent` rather than by changing a real setting, so
/// each size below is exact and nothing depends on the simulator's own category.
@MainActor
struct DynamicTypeTests {

    /// The base every note starts from, which the metrics scale rather than replace.
    private let base = AppConstants.Layout.defaultFontSize

    /// Only the end-to-end test below needs it: a real coordinator reads the zoom from defaults.
    private let scratchDefaults: ScratchDefaults

    init() throws {
        scratchDefaults = try ScratchDefaults(name: "DynamicTypeTests")
    }

    private func editorPointSize(
        at category: UIContentSizeCategory, plainText: Bool = false
    ) -> CGFloat {
        var size: CGFloat = 0
        UITraitCollection(preferredContentSizeCategory: category).performAsCurrent {
            size = PlatformFont.editorBody(plainText: plainText, size: base).pointSize
        }
        return size
    }

    /// At the default category the metrics are the identity, so a user who has never touched the
    /// setting sees the same 16 pt note as before.
    @Test(arguments: [false, true])
    func theDefaultContentSizeLeavesTheNoteExactlyWhereItWas(plainText: Bool) {
        #expect(editorPointSize(at: .large, plainText: plainText) == base)
    }

    /// The defect this closes: a note that stayed 16 pt for someone who had asked the system for
    /// bigger text.
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

    /// Monotonic across the whole range, which says the base is scaled rather than swapped for a
    /// text style's own size: `.body` at `.large` is 17 pt, so a replaced font would sit at 17 and
    /// still pass the two tests above.
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

    /// Both modes scale together, or toggling the mode would jump the note's size.
    @Test(
        arguments: [UIContentSizeCategory.extraSmall, .large, .accessibilityExtraExtraLarge])
    func bothModesScaleTogether(category: UIContentSizeCategory) {
        #expect(
            editorPointSize(at: category, plainText: true)
                == editorPointSize(at: category, plainText: false))
    }

    /// Every other cut is derived from the body font, so scaling that one is enough: bold, italic
    /// and their combination all arrive at the scaled size.
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

    /// The whole path, on the real views: the setting changes and the characters already on screen
    /// are redrawn at the new size.
    ///
    /// Through a real `Coordinator` and `MarkdownTextView` rather than a spy, because `apply`'s
    /// `appearance != configuredStyling` guard can throw the repaint away while every measurement
    /// above still passes; only the font in the text storage shows that.
    ///
    /// Posted inside `performAsCurrent` because the post is synchronous, so the appearance the
    /// coordinator builds in response resolves under the category set here.
    @Test func aSystemTextSizeChangeRedrawsTheNoteAlreadyOnScreen() throws {
        let coordinator = IOSRichTextEditor.Coordinator(
            statistics: EditorStatistics(), defaults: scratchDefaults.defaults,
            notificationCenter: NotificationCenter())
        let container = UIView()
        coordinator.setup(
            container: container, notes: [NoteItem(id: 0, text: "**pass**: rotate-me")],
            selectedIndex: 0)

        let view = try #require(container.subviews.first as? MarkdownTextView)
        let before = try #require(font(in: view))

        UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
            .performAsCurrent {
                NotificationCenter.default.post(
                    name: UIContentSizeCategory.didChangeNotification, object: nil)
            }

        let after = try #require(font(in: view))

        #expect(after.pointSize > before.pointSize)
        #expect(view.text == "pass: rotate-me", "and the text itself is untouched")
    }

    private func font(in view: MarkdownTextView) -> UIFont? {
        guard view.textStorage.length > 0 else { return nil }
        return view.textStorage.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
    }

    /// The zoom stored in defaults stays the base the scaling starts from, rather than being
    /// replaced by it. The appearance has to be *built* inside `performAsCurrent`, not merely read
    /// there: `baseFont` is resolved by `Appearance.init`, so one constructed outside the closure
    /// has already scaled by whatever category was ambient.
    @Test func theStoredSizeIsStillTheBase() {
        var scaled: CGFloat = 0
        UITraitCollection(preferredContentSizeCategory: .large).performAsCurrent {
            scaled = MarkdownStyling.Appearance(plainText: false, fontSize: 24).baseFont.pointSize
        }

        #expect(scaled == 24, "at the default category the base is what is drawn")
    }

    /// And a larger category scales that stored size rather than replacing it.
    @Test func theStoredSizeIsWhatALargerCategoryScales() {
        var scaled: CGFloat = 0
        UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge)
            .performAsCurrent {
                scaled = MarkdownStyling.Appearance(plainText: false, fontSize: 24).baseFont.pointSize
            }

        #expect(scaled > 24)
    }
}
