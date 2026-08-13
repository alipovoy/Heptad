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

    init() throws {
        coordinator = makeTestCoordinator()
        scrollView = try #require(
            coordinator.makeEditorView(for: NoteItem(id: 0)) as? NSScrollView)
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
            boldTint: NotePalette.boldTint(forNoteIndex: 0))
    }

    func baseFont(plainText: Bool) -> NSFont {
        appearance(plainText: plainText).baseFont
    }

    /// Repaints the view in the given mode, the way `update` does on its way in.
    func configure(plainText: Bool) {
        coordinator.configure(scrollView, appearance: appearance(plainText: plainText))
    }
}
