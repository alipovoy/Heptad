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

    /// The appearance the coordinator would build for a note in this mode, at the default zoom.
    private func appearance(plainText: Bool) -> MarkdownStyling.Appearance {
        MarkdownStyling.Appearance(
            plainText: plainText, fontSize: AppConstants.Layout.defaultFontSize)
    }

    private func baseFont(plainText: Bool) -> NSFont {
        appearance(plainText: plainText).baseFont
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
        coordinator.configure(scrollView, appearance: appearance(plainText: false))

        let styled = try font(at: 8)
        try #require(NSFontManager.shared.traits(of: styled).contains(.boldFontMask))

        coordinator.configure(scrollView, appearance: appearance(plainText: true))
        #expect(try font(at: 8) == baseFont(plainText: true), "Plain mode stops styling it")
        #expect(textView.string == "pass: **rotate-me**", "and changes not one character")

        coordinator.configure(scrollView, appearance: appearance(plainText: false))
        #expect(try font(at: 8) == styled, "Switching back brings the styling back")
    }

    /// Repeatedly, not just once: the mode is derived from the note on every repaint, so there
    /// is no state to wear down. Under the old flattening implementation the second round trip
    /// had nothing left to restore.
    @Test func switchingModesIsReversibleIndefinitely() throws {
        let textView = try textView()
        textView.string = "- [ ] rotate ~~the~~ *keys*"

        for _ in 0..<5 {
            coordinator.configure(scrollView, appearance: appearance(plainText: true))
            coordinator.configure(scrollView, appearance: appearance(plainText: false))
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

        coordinator.configure(scrollView, appearance: appearance(plainText: false))
        let once = try font(at: 2)
        coordinator.configure(scrollView, appearance: appearance(plainText: false))

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
        coordinator.configure(scrollView, appearance: appearance(plainText: true))

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
        coordinator.configure(scrollView, appearance: appearance(plainText: true))
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
        coordinator.configure(scrollView, appearance: appearance(plainText: false))
        textView.setSelectedRange(NSRange(location: 0, length: 4))

        manager.toggleEmphasis(.strong, on: textView)

        #expect(textView.string == "**user**: admin")
    }

    // MARK: - Pasting

    /// ⌘V follows the same guard the formatting commands do. Converting a pasted bold run to
    /// `**secret**` in a note where ⌘B is silenced would put delimiters in it that none of its
    /// own commands could take back out — the one thing the whole Markdown swap exists to stop.
    @Test func pastingIntoAPlainNoteBringsNoDelimiters() throws {
        let textView = try textView()
        textView.string = ""
        coordinator.configure(scrollView, appearance: appearance(plainText: true))

        let scratch = ScratchPasteboard()
        scratch.write { $0.setData(Data("<b>secret</b>".utf8), forType: .html) }
        let shortcutManager = EditorShortcutManager(
            defaults: scratchDefaults.defaults, pasteboard: scratch.pasteboard)

        shortcutManager.pasteAsMarkdown(on: textView)

        #expect(textView.string == "secret")
    }

    /// The same clipboard in a rich note does keep the bold, as source.
    @Test func pastingIntoARichNoteConvertsTheFormatting() throws {
        let textView = try textView()
        textView.string = ""
        coordinator.configure(scrollView, appearance: appearance(plainText: false))

        let scratch = ScratchPasteboard()
        scratch.write { $0.setData(Data("<b>secret</b>".utf8), forType: .html) }
        let shortcutManager = EditorShortcutManager(
            defaults: scratchDefaults.defaults, pasteboard: scratch.pasteboard)

        shortcutManager.pasteAsMarkdown(on: textView)

        #expect(textView.string == "**secret**")
    }

    // MARK: - Repainting

    /// An edit repaints the lines it landed on, not the whole note — a construct never spans
    /// lines, so nothing further can have changed. The result has to be indistinguishable from
    /// repainting everything, which is what this compares it against.
    @Test func editingOneLineRepaintsItToTheSameResultAsRepaintingAll() throws {
        let textView = try textView()
        coordinator.configure(scrollView, appearance: appearance(plainText: false))
        textView.string = "**one**\nplain here\n_three_"
        textView.restyle()

        let storage = try #require(textView.textStorage)
        storage.replaceCharacters(in: NSRange(location: 8, length: 10), with: "~~struck~~")

        let afterEdit = NSAttributedString(attributedString: storage)
        textView.restyle()

        #expect(afterEdit.isEqual(to: storage), "The line-scoped repaint left the note as a full one would")
    }

    // MARK: - Copying

    /// A note leaves on the clipboard as its own characters.
    ///
    /// The view is `isRichText` so it can draw its derived styling, and AppKit would otherwise
    /// write that painted-on bold as RTF — which ⌘V reads back in preference to the plain
    /// flavor, re-deriving delimiters from the paint. Copying `**keys**` and pasting it returned
    /// `****keys****`, corrupting the note it came from.
    @Test(.bug(id: 117))
    func copyingAStyledNoteRoundTripsExactly() throws {
        let textView = try textView()
        textView.string = "**keys** and _more_"
        coordinator.configure(scrollView, appearance: appearance(plainText: false))
        textView.setSelectedRange(NSRange(location: 0, length: 19))

        // No rich flavor offered, and the plain one still spelled the way AppKit's own writer
        // recognises — returning `[.string]` here makes `writeSelection` fail and copy nothing.
        #expect(textView.writablePasteboardTypes.isEmpty == false)
        #expect(textView.writablePasteboardTypes.allSatisfy { $0 != .rtf && $0 != .rtfd })

        // `writeSelection(to:types:)` writes into types the caller has already declared, which
        // is what `copy(_:)` does for it.
        let scratch = ScratchPasteboard()
        scratch.pasteboard.declareTypes(textView.writablePasteboardTypes, owner: nil)
        #expect(textView.writeSelection(to: scratch.pasteboard, types: textView.writablePasteboardTypes))

        #expect(scratch.pasteboard.markdownForPaste() == "**keys** and _more_")
    }
}
