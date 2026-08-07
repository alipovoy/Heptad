import AppKit
import SwiftUI
import Testing

@testable import Heptad

/// Per-note plain-text mode, where it is applied: the text view the coordinator configures,
/// and the formatting shortcuts that have to stop working in it.
///
/// The mode is a rendering choice now, not a transform. It used to flatten the note's
/// attributes, which made switching a one-way trip that took the formatting with it — the second
/// half of #117. Most of what this suite pins is that switching changes *nothing* about the text.
@MainActor
final class PlainTextModeTests {
    private let coordinator: MacRichTextEditor.Coordinator
    private let scrollView: NSScrollView
    private let scratchDefaults: ScratchDefaults
    private let manager: EditorShortcutManager

    init() throws {
        coordinator = makeTestCoordinator()

        // The coordinator vends the same scroll-view-wrapped text view the app installs, so
        // `configure` is exercised through the shape it actually meets.
        scrollView = try #require(
            coordinator.makeEditorView(for: NoteItem(id: 0)) as? NSScrollView)

        scratchDefaults = try ScratchDefaults(name: "PlainTextModeTests")
        manager = EditorShortcutManager(defaults: scratchDefaults.defaults)
    }

    private func textView() throws -> MarkdownTextView {
        try #require(scrollView.documentView as? MarkdownTextView)
    }

    private func font(at location: Int) throws -> NSFont {
        let storage = try #require(try textView().textStorage)
        return try #require(storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont)
    }

    private func baseFont(plainText: Bool) -> NSFont {
        MarkdownStyling.Appearance(plainText: plainText).baseFont
    }

    // MARK: - Applying the mode

    /// Driven through `setup` rather than `makeEditorView`: the mode lives only in `configure`,
    /// and the coordinator is what applies it to a view on its way in. Calling the factory alone
    /// would assert about a view the app never installs.
    @Test func aPlainNoteOpensMonospacedWithItsMarkdownLiteral() throws {
        let container = NSView()
        let note = NoteItem(id: 1, text: "pass: **rotate-me**", isPlainText: true)

        coordinator.setup(container: container, notes: [note], selectedIndex: 0)

        let scrollView = try #require(container.subviews.first as? NSScrollView)
        let textView = try #require(scrollView.documentView as? MarkdownTextView)
        #expect(textView.string == "pass: **rotate-me**")

        let storage = try #require(textView.textStorage)
        let mono = baseFont(plainText: true)
        for location in 0..<storage.length {
            let font = storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont
            #expect(font == mono, "Plain mode draws the source and styles none of it")
        }
    }

    /// A rich note opens proportional, with its markdown drawn.
    @Test func aRichNoteOpensProportionalWithItsMarkdownStyled() throws {
        let container = NSView()
        let note = NoteItem(id: 1, text: "pass: **rotate-me**")

        coordinator.setup(container: container, notes: [note], selectedIndex: 0)

        let scrollView = try #require(container.subviews.first as? NSScrollView)
        let textView = try #require(scrollView.documentView as? MarkdownTextView)
        let storage = try #require(textView.textStorage)

        #expect(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
            == baseFont(plainText: false), "Unstyled text takes the base font")

        // "pass: **rotate-me**" — location 8 is inside the delimited run.
        let inRun = try #require(storage.attribute(.font, at: 8, effectiveRange: nil) as? NSFont)
        #expect(NSFontManager.shared.traits(of: inRun).contains(.boldFontMask))
    }

    /// Opening a note is not an edit to it — the fix's central promise, checked at the point
    /// where the old implementation broke it by flattening on the way in.
    @Test func openingAPlainNoteKeepsItsTextAndItsMarkdown() throws {
        let container = NSView()
        let note = NoteItem(id: 1, text: "pass: **rotate-me**", isPlainText: true)

        coordinator.setup(container: container, notes: [note], selectedIndex: 0)

        #expect(note.text == "pass: **rotate-me**", "Opening a note is not an edit to it")
    }

    /// A cached view comes back in its note's *current* mode, not the one it was built in.
    ///
    /// This is the case #103 fixed, driven through the real text view. `update` used to apply
    /// the mode only on the early return for the note already showing, so a view returning from
    /// the cache kept whatever mode it was created with.
    @Test(.bug(id: 103))
    func aCachedViewComesBackInItsNotesCurrentMode() throws {
        let container = NSView()
        let notes = [NoteItem(id: 0, text: "**bold**"), NoteItem(id: 1)]
        coordinator.setup(container: container, notes: notes, selectedIndex: 0)

        // Leave note 0, flip its mode while its view is off screen, then come back to it.
        coordinator.update(notes: notes, selectedIndex: 1)
        notes[0].isPlainText = true
        coordinator.update(notes: notes, selectedIndex: 0)

        let scrollView = try #require(container.subviews.first as? NSScrollView)
        let textView = try #require(scrollView.documentView as? MarkdownTextView)
        let storage = try #require(textView.textStorage)
        #expect(storage.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
            == baseFont(plainText: true))
    }

    // MARK: - Switching, in both directions

    /// The bug this fix exists for, in its second form: switching modes used to clear the
    /// note's formatting for good. Now the source is untouched and the styling comes back.
    @Test(.bug(id: 117))
    func switchingModesAndBackRestoresTheStyling() throws {
        let textView = try textView()
        textView.string = "pass: **rotate-me**"
        coordinator.configure(scrollView, for: NoteItem(id: 0))

        let styled = try font(at: 8)
        try #require(NSFontManager.shared.traits(of: styled).contains(.boldFontMask))

        coordinator.configure(scrollView, for: NoteItem(id: 0, isPlainText: true))
        #expect(try font(at: 8) == baseFont(plainText: true), "Plain mode stops styling it")
        #expect(textView.string == "pass: **rotate-me**", "and changes not one character")

        coordinator.configure(scrollView, for: NoteItem(id: 0))
        #expect(try font(at: 8) == styled, "Switching back brings the styling back")
    }

    /// Repeatedly, not just once: the mode is derived from the note on every repaint, so there
    /// is no state to wear down. Under the old flattening implementation the second round trip
    /// had nothing left to restore.
    @Test func switchingModesIsReversibleIndefinitely() throws {
        let textView = try textView()
        textView.string = "- [ ] rotate ~~the~~ *keys*"

        for _ in 0..<5 {
            coordinator.configure(scrollView, for: NoteItem(id: 0, isPlainText: true))
            coordinator.configure(scrollView, for: NoteItem(id: 0))
        }

        #expect(textView.string == "- [ ] rotate ~~the~~ *keys*")
        let storage = try #require(textView.textStorage)
        #expect(
            storage.attribute(.strikethroughStyle, at: 16, effectiveRange: nil) as? Int
                == NSUnderlineStyle.single.rawValue)
    }

    /// `configure` runs on every update and is a repaint, so running it twice has to land in the
    /// same place. It no longer needs a guard against that — under the old implementation an
    /// unguarded second call re-flattened the note.
    @Test func configuringTwiceLeavesTheSameResult() throws {
        let textView = try textView()
        textView.string = "**bold**"

        coordinator.configure(scrollView, for: NoteItem(id: 0))
        let once = try font(at: 2)
        coordinator.configure(scrollView, for: NoteItem(id: 0))

        #expect(try font(at: 2) == once)
        #expect(textView.string == "**bold**")
    }

    // MARK: - Paste

    /// Styled text arriving from another app lands as characters, in the note's own font.
    ///
    /// Read from a private pasteboard rather than `paste(_:)`, which would take over the user's
    /// real clipboard for the length of the run. This is the raw AppKit read — the path that used
    /// to leave attributes behind — so it proves the repaint erases them wherever they enter.
    @Test func pastingStyledTextIntoAPlainNoteDropsTheStyling() throws {
        let textView = try textView()
        coordinator.configure(scrollView, for: NoteItem(id: 0, isPlainText: true))

        let styled = NSAttributedString(
            string: "rotate-me",
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: 24),
                .foregroundColor: NSColor.systemRed
            ])
        let scratch = ScratchPasteboard()
        scratch.write {
            $0.setData(
                styled.rtf(from: NSRange(location: 0, length: styled.length)) ?? Data(),
                forType: .rtf)
            $0.setString(styled.string, forType: .string)
        }

        #expect(textView.readSelection(from: scratch.pasteboard))
        textView.restyle()

        #expect(textView.string == "rotate-me")
        #expect(
            try font(at: 0) == baseFont(plainText: true),
            "The pasted run takes the note's own font, not the source app's")

        let storage = try #require(textView.textStorage)
        #expect(
            storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
                == .adaptiveEditorText,
            "and the note's own colour")
    }

    /// The reported symptom of #117, end to end: paste formatted text, press ⌘Z, and the text
    /// goes but the formatting stays — colour and alignment left in `typingAttributes`, where
    /// no command could reach them, so everything typed afterwards came out wearing them.
    ///
    /// Driven through the raw AppKit read rather than ⌘V, which no longer goes anywhere near
    /// `paste(_:)`. That is deliberate: this pins the *repair*, not the avoidance, so the note
    /// stays clean even if something else ever puts attributes into the view.
    @Test(.bug(id: 117))
    func undoingAPasteLeavesNoFormattingBehind() throws {
        // `isReleasedWhenClosed` off before anything else: AppKit's default of releasing the
        // window on close over-releases it under ARC and takes the test process down with it.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: .borderless,
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }

        let container = NSView()
        window.contentView?.addSubview(container)
        let note = NoteItem(id: 0)
        coordinator.setup(container: container, notes: [note], selectedIndex: 0)

        let scrollView = try #require(container.subviews.first as? NSScrollView)
        let textView = try #require(scrollView.documentView as? MarkdownTextView)

        let centred = NSMutableParagraphStyle()
        centred.alignment = .center
        let styled = NSAttributedString(
            string: "formatted",
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: 24),
                .foregroundColor: NSColor.systemRed,
                .paragraphStyle: centred
            ])
        let scratch = ScratchPasteboard()
        scratch.write {
            $0.setData(
                styled.rtf(from: NSRange(location: 0, length: styled.length)) ?? Data(),
                forType: .rtf)
        }

        try #require(textView.readSelection(from: scratch.pasteboard))
        try #require(textView.string == "formatted")

        textView.undoManager?.undo()

        #expect(textView.string == "", "The text goes")

        // And so does the formatting, which is the half that used to survive.
        #expect(
            textView.typingAttributes[.font] as? NSFont == baseFont(plainText: false),
            "Typing after the undo is the note's own font, not the clipboard's")
        #expect(textView.typingAttributes[.foregroundColor] as? NSColor == .adaptiveEditorText)
        #expect(textView.typingAttributes[.paragraphStyle] == nil, "No alignment is left behind")
    }

    // MARK: - Formatting shortcuts

    /// ⌘B, ⌘I and ⌘⇧X have nothing worth applying in a note that leaves its markdown literal —
    /// the delimiters would be noise with nothing to show for them.
    @Test func formattingShortcutsDoNothingInAPlainNote() throws {
        let textView = try textView()
        textView.string = "user: admin"
        coordinator.configure(scrollView, for: NoteItem(id: 0, isPlainText: true))
        textView.setSelectedRange(NSRange(location: 0, length: 4))

        manager.toggleEmphasis(.strong, on: textView)
        manager.toggleEmphasis(.emphasis, on: textView)
        manager.toggleStrikethrough(on: textView)

        #expect(textView.string == "user: admin")
    }

    /// The same commands still work in a rich note — the guard is on the mode, not on the
    /// commands. `EditorFormattingTests` covers what they do in detail.
    @Test func formattingShortcutsStillWorkInARichNote() throws {
        let textView = try textView()
        textView.string = "user: admin"
        coordinator.configure(scrollView, for: NoteItem(id: 0))
        textView.setSelectedRange(NSRange(location: 0, length: 4))

        manager.toggleEmphasis(.strong, on: textView)

        #expect(textView.string == "**user**: admin")
    }
}
