import AppKit
import Testing

@testable import Heptad

/// A real editor view, vended the way the app vends it.
///
/// `makeEditorView` hands back the scroll-view-wrapped `MarkdownTextView` the coordinator installs,
/// so everything driven through this fixture meets `configure`, `load` and the storage delegate in
/// the shape they actually meet in the app — rather than a bare `NSTextView` that would take the
/// plain-text branch of every mode question and assert nothing.
@MainActor
final class MarkdownEditorFixture {
    let coordinator: MacRichTextEditor.Coordinator
    let scrollView: NSScrollView

    /// The same object the coordinator reports counts into, so a test can read the numbers the
    /// statistics bar would be showing.
    let statistics: EditorStatistics

    init() throws {
        let statistics = EditorStatistics()
        self.statistics = statistics
        coordinator = makeTestCoordinator(statistics: statistics)
        scrollView = try #require(coordinator.makeEditorView() as? NSScrollView)
    }

    func textView() throws -> MarkdownTextView {
        try #require(scrollView.documentView as? MarkdownTextView)
    }

    func font(at location: Int) throws -> NSFont {
        let storage = try #require(try textView().textStorage)
        return try #require(storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont)
    }

    /// The appearance the coordinator would build for a note in this mode, at the default zoom.
    ///
    /// Carries note 0's bold tint, because the coordinator's does — the view under test is built
    /// for `NoteItem(id: 0)` above. Leaving it out would let a bold run come up in the body-text
    /// colour here and in the note's own colour in the app.
    func appearance(plainText: Bool) -> MarkdownStyling.Appearance {
        MarkdownStyling.Appearance(
            plainText: plainText, fontSize: AppConstants.Layout.defaultFontSize,
            tintedNoteIndex: 0)
    }

    func baseFont(plainText: Bool) -> NSFont {
        appearance(plainText: plainText).baseFont
    }

    /// Repaints the view in the given mode, the way `update` does on its way in.
    func configure(plainText: Bool) {
        coordinator.configure(scrollView, appearance: appearance(plainText: plainText))
    }

    /// A formatted buffer loaded the way a note switch loads one, so a command meets the buffer it
    /// meets in the app: traits derived from markdown, and bare line terminators between the lines.
    ///
    /// A freshly typed line answers differently — every character in it can carry a trait — which
    /// is why a bug that only shows on a reloaded note survived the suite.
    @discardableResult
    func loaded(_ markdown: String) throws -> MarkdownTextView {
        configure(plainText: false)
        let textView = try textView()
        textView.load(markdown: markdown)
        return textView
    }
}
