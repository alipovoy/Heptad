import AppKit
import SwiftUI
import Testing

@testable import Heptad

/// Per-note plain-text mode, where it is applied: the text view the coordinator configures,
/// and the formatting shortcuts that have to stop working in it.
@MainActor
final class PlainTextModeTests {
    private let coordinator: MacRichTextEditor.Coordinator
    private let scrollView: NSScrollView
    private let suiteName: String
    private let defaults: UserDefaults
    private let manager: EditorShortcutManager

    init() throws {
        coordinator = MacRichTextEditor.Coordinator(statistics: EditorStatistics())

        // The coordinator vends the same scroll-view-wrapped text view the app installs, so
        // `configure` is exercised through the shape it actually meets.
        scrollView = try #require(
            coordinator.makeEditorView(for: NoteItem(id: 0)) as? NSScrollView)

        suiteName = "PlainTextModeTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        manager = EditorShortcutManager(defaults: defaults)
    }

    isolated deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func textView() throws -> NSTextView {
        try #require(scrollView.documentView as? NSTextView)
    }

    private func font(at location: Int) throws -> NSFont {
        let storage = try #require(try textView().textStorage)
        return try #require(storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont)
    }

    // MARK: - Storage

    @Test func notesAreRichTextUntilToldOtherwise() {
        #expect(NoteItem(id: 0).isPlainText == false)
    }

    // MARK: - Applying the mode

    /// Driven through `setup` rather than `makeEditorView`: the mode now lives only in
    /// `configure`, and the coordinator is what applies it to a view on its way in. Calling the
    /// factory alone would assert about a view the app never installs.
    @Test func aPlainNoteOpensPlainAndMonospaced() throws {
        let container = NSView()
        let note = NoteItem(id: 1, isPlainText: true)

        coordinator.setup(container: container, notes: [note], selectedIndex: 0)

        let scrollView = try #require(container.subviews.first as? NSScrollView)
        let textView = try #require(scrollView.documentView as? NSTextView)
        #expect(textView.isRichText == false)
        #expect(textView.font == .monospacedSystemFont(
            ofSize: AppConstants.Layout.defaultFontSize, weight: .regular))
    }

    /// A plain note's stored text survives being opened.
    ///
    /// The order `makeCachedEditorView` keeps is what this pins: the mode is applied to an empty
    /// view and the content loaded after it. Flattening a *loaded* view instead would report an
    /// edit the user never made, and applying the mode before the saver exists — or before the
    /// coordinator knows which note is showing — would route that edit to the wrong note.
    @Test func openingAPlainNoteKeepsItsText() throws {
        let container = NSView()
        let stored = try #require(NoteItem.rtfData(from: NSAttributedString(string: "rotate-me")))
        let note = NoteItem(id: 1, rtfData: stored, isPlainText: true)

        coordinator.setup(container: container, notes: [note], selectedIndex: 0)

        let scrollView = try #require(container.subviews.first as? NSScrollView)
        let textView = try #require(scrollView.documentView as? NSTextView)
        #expect(textView.string == "rotate-me")
        #expect(note.rtfData == stored, "Opening a note is not an edit to it")
    }

    /// A rich note opens proportional. The counterpart to the plain case above: `configure`
    /// declines to touch a view that is already in the note's mode, so the font a rich note
    /// opens with is the one `makeEditorView` established, and nothing re-applies it.
    @Test func aRichNoteOpensProportional() throws {
        let container = NSView()

        coordinator.setup(container: container, notes: [NoteItem(id: 1)], selectedIndex: 0)

        let scrollView = try #require(container.subviews.first as? NSScrollView)
        let textView = try #require(scrollView.documentView as? NSTextView)
        #expect(textView.isRichText)
        #expect(textView.font == .systemFont(ofSize: AppConstants.Layout.defaultFontSize))
    }

    /// A cached view comes back in its note's *current* mode, not the one it was built in.
    ///
    /// This is the case #103 fixed, driven through the real text view rather than the
    /// coordinator's spy. `update` used to apply the mode only on the early return for the note
    /// already showing, so a view returning from the cache kept whatever mode it was created
    /// with — the note would come back proportional after being switched to plain.
    @Test(.bug(id: 103))
    func aCachedViewComesBackInItsNotesCurrentMode() throws {
        let container = NSView()
        let notes = [NoteItem(id: 0), NoteItem(id: 1)]
        coordinator.setup(container: container, notes: notes, selectedIndex: 0)

        // Leave note 0, flip its mode while its view is off screen, then come back to it.
        coordinator.update(notes: notes, selectedIndex: 1)
        notes[0].isPlainText = true
        coordinator.update(notes: notes, selectedIndex: 0)

        let scrollView = try #require(container.subviews.first as? NSScrollView)
        let textView = try #require(scrollView.documentView as? NSTextView)
        #expect(textView.isRichText == false)
        #expect(textView.font == .monospacedSystemFont(
            ofSize: AppConstants.Layout.defaultFontSize, weight: .regular))
    }

    /// Switching to plain keeps every character and drops only how it looked — the note is
    /// flattened to one uniform font, not emptied.
    @Test func switchingToPlainFlattensTheFormattingAndKeepsTheText() throws {
        let textView = try textView()
        textView.string = "user: admin"
        textView.textStorage?.addAttribute(
            .font, value: NSFont.boldSystemFont(ofSize: 24),
            range: NSRange(location: 0, length: 4))

        coordinator.configure(scrollView, for: NoteItem(id: 0, isPlainText: true))

        #expect(textView.string == "user: admin")
        #expect(textView.isRichText == false)
        let monospaced = NSFont.monospacedSystemFont(
            ofSize: AppConstants.Layout.defaultFontSize, weight: .regular)
        #expect(try font(at: 0) == monospaced, "The styled run is flattened")
        #expect(try font(at: 6) == monospaced, "So is the rest")
    }

    @Test func switchingBackToRichRestoresTheProportionalFont() throws {
        let textView = try textView()
        textView.string = "user: admin"

        coordinator.configure(scrollView, for: NoteItem(id: 0, isPlainText: true))
        coordinator.configure(scrollView, for: NoteItem(id: 0, isPlainText: false))

        #expect(textView.isRichText)
        #expect(try font(at: 0) == .systemFont(ofSize: AppConstants.Layout.defaultFontSize))
    }

    /// `configure` runs on every update, so it has to be inert when the mode has not moved.
    /// Left unguarded it would re-flatten a rich note's formatting on the next keystroke.
    @Test func configuringAnUnchangedModeLeavesTheTextAlone() throws {
        let textView = try textView()
        textView.string = "user: admin"
        let bold = NSFont.boldSystemFont(ofSize: 24)
        textView.textStorage?.addAttribute(
            .font, value: bold, range: NSRange(location: 0, length: 4))

        coordinator.configure(scrollView, for: NoteItem(id: 0))

        #expect(try font(at: 0) == bold)
    }

    // MARK: - Paste

    /// The other half of what `isRichText = false` buys: styled text arriving from another app
    /// lands as text. Read from a private pasteboard rather than `paste(_:)`, which would take
    /// over the user's real clipboard for the length of the run.
    @Test func pastingStyledTextIntoAPlainNoteDropsTheStyling() throws {
        let textView = try textView()
        coordinator.configure(scrollView, for: NoteItem(id: 0, isPlainText: true))

        let styled = NSAttributedString(
            string: "rotate-me", attributes: [.font: NSFont.boldSystemFont(ofSize: 24)])
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("PlainTextModeTests.\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setData(
            try #require(styled.rtf(from: NSRange(location: 0, length: styled.length))),
            forType: .rtf)
        pasteboard.setString(styled.string, forType: .string)

        #expect(textView.readSelection(from: pasteboard))

        #expect(textView.string == "rotate-me")
        #expect(
            try font(at: 0) == .monospacedSystemFont(
                ofSize: AppConstants.Layout.defaultFontSize, weight: .regular),
            "The pasted run takes the note's own font, not the source app's")
    }

    // MARK: - Formatting shortcuts

    /// ⌘B, ⌘I and ⌘⇧X have nothing to apply in a note that is one uniform font.
    @Test func formattingShortcutsDoNothingInAPlainNote() throws {
        let textView = try textView()
        textView.string = "user: admin"
        coordinator.configure(scrollView, for: NoteItem(id: 0, isPlainText: true))
        textView.setSelectedRange(NSRange(location: 0, length: 4))
        let before = try font(at: 0)

        manager.toggleFontTrait(.boldFontMask, on: textView)
        manager.toggleFontTrait(.italicFontMask, on: textView)
        manager.toggleStrikethrough(on: textView)

        #expect(try font(at: 0) == before)
        let storage = try #require(textView.textStorage)
        #expect(storage.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) == nil)
    }

    /// The same commands still work in a rich note — the guard is on the mode, not on the
    /// commands. `EditorFormattingTests` covers what they do in detail.
    @Test func formattingShortcutsStillWorkInARichNote() throws {
        let textView = try textView()
        textView.string = "user: admin"
        textView.textStorage?.addAttribute(
            .font, value: NSFont.systemFont(ofSize: 16), range: NSRange(location: 0, length: 11))
        textView.setSelectedRange(NSRange(location: 0, length: 4))

        manager.toggleFontTrait(.boldFontMask, on: textView)

        #expect(
            NSFontManager.shared.traits(of: try font(at: 0)).contains(.boldFontMask))
    }
}
