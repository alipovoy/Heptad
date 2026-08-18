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

    /// The coordinator's own two seams, so a suite can step the zoom or flush the savers without
    /// touching the shipping defaults domain or every other coordinator in the process.
    let scratchDefaults: ScratchDefaults
    let notificationCenter = NotificationCenter()

    init() throws {
        let statistics = EditorStatistics()
        self.statistics = statistics
        scratchDefaults = try ScratchDefaults(name: "MarkdownEditorFixture")
        coordinator = makeTestCoordinator(
            statistics: statistics, defaults: scratchDefaults.defaults,
            notificationCenter: notificationCenter)
        scrollView = try #require(coordinator.makeEditorView() as? NSScrollView)
    }

    func textView(sourceLocation: SourceLocation = #_sourceLocation) throws -> MarkdownTextView {
        try #require(scrollView.documentView as? MarkdownTextView, sourceLocation: sourceLocation)
    }

    /// Which characters of the buffer carry `emphasis` — see `NSAttributedString.carrying(_:)` for
    /// why a command's assertion belongs here rather than on what the note stores.
    func carrying(_ emphasis: Emphasis) throws -> String {
        try #require(try textView().textStorage).carrying(emphasis)
    }

    func font(
        at location: Int, sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> NSFont {
        let storage = try #require(
            try textView(sourceLocation: sourceLocation).textStorage,
            sourceLocation: sourceLocation)
        return try #require(
            storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont,
            sourceLocation: sourceLocation)
    }

    /// The appearance the coordinator would build for note 0 in this mode. Asked of the coordinator
    /// rather than assembled here, so a field `Appearance` gains cannot go missing on this side and
    /// leave the fixture drawing what the app does not.
    func appearance(plainText: Bool) -> MarkdownStyling.Appearance {
        coordinator.appearance(for: NoteItem(id: 0, isPlainText: plainText), at: 0)
    }

    func baseFont(plainText: Bool) -> NSFont {
        appearance(plainText: plainText).baseFont
    }

    /// Repaints the view in the given mode, the way `update` does on its way in.
    func configure(plainText: Bool) {
        coordinator.configure(scrollView, appearance: appearance(plainText: plainText))
    }

    /// A formatted buffer loaded the way a note switch loads one: traits derived from markdown, and
    /// bare line terminators between the lines. A freshly typed line answers differently, since
    /// every character in it can carry a trait.
    @discardableResult
    func loaded(_ markdown: String) throws -> MarkdownTextView {
        configure(plainText: false)
        let textView = try textView()
        textView.load(markdown: markdown)
        return textView
    }
}
