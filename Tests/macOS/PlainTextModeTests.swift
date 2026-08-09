import AppKit
import Testing

@testable import Heptad

/// Per-note plain-text mode, where it is applied: the text view the coordinator configures, and
/// the commands that have to stop working in it.
///
/// The mode decides what the editor is *holding*: formatted mode holds rich text with the
/// delimiters parsed away, plain mode holds the source. Switching converts between the two, so
/// most of what this suite pins is that the conversion is lossless — the note that comes out of a
/// round trip is the note that went in (#124), and switching is never an edit to it (#117).
///
/// `MarkdownTextViewTests` covers what the view does regardless of mode.
@MainActor
struct PlainTextModeTests {
    private let fixture: MarkdownEditorFixture
    private let scratchDefaults: ScratchDefaults
    private let manager: EditorShortcutManager

    init() throws {
        fixture = try MarkdownEditorFixture()
        scratchDefaults = try ScratchDefaults(name: "PlainTextModeTests")
        manager = EditorShortcutManager(defaults: scratchDefaults.defaults)
    }

    // MARK: - Applying the mode

    /// Driven through `setup` rather than `makeEditorView`: the mode lives only in `configure`,
    /// and the coordinator is what applies it to a view on its way in. Calling the factory alone
    /// would assert about a view the app never installs.
    @Test func aPlainNoteOpensMonospacedWithItsMarkdownLiteral() throws {
        let container = NSView()
        let note = NoteItem(id: 1, text: "pass: **rotate-me**", isPlainText: true)

        fixture.coordinator.setup(container: container, notes: [note], selectedIndex: 0)

        let scrollView = try #require(container.subviews.first as? NSScrollView)
        let textView = try #require(scrollView.documentView as? MarkdownTextView)
        #expect(textView.string == "pass: **rotate-me**")

        let storage = try #require(textView.textStorage)
        let mono = fixture.baseFont(plainText: true)
        for location in 0..<storage.length {
            let font = storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont
            #expect(font == mono, "Plain mode draws the source and styles none of it")
        }
    }

    /// A rich note opens proportional, with its markdown *drawn* rather than shown: the
    /// delimiters were parsed away on the way in and the run they described is bold.
    @Test(.bug(id: 124)) func aRichNoteOpensProportionalWithItsMarkdownDrawn() throws {
        let container = NSView()
        let note = NoteItem(id: 1, text: "pass: **rotate-me**")

        fixture.coordinator.setup(container: container, notes: [note], selectedIndex: 0)

        let scrollView = try #require(container.subviews.first as? NSScrollView)
        let textView = try #require(scrollView.documentView as? MarkdownTextView)
        let storage = try #require(textView.textStorage)

        #expect(textView.string == "pass: rotate-me", "No delimiters on screen")
        #expect(
            storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
                == fixture.baseFont(plainText: false), "Unstyled text takes the base font")

        // "pass: rotate-me" — location 8 is inside the run the delimiters described.
        let inRun = try #require(storage.attribute(.font, at: 8, effectiveRange: nil) as? NSFont)
        #expect(inRun.isBold)
    }

    /// Opening a note is not an edit to it — the fix's central promise, checked at the point
    /// where the old implementation broke it by flattening on the way in.
    @Test func openingAPlainNoteKeepsItsTextAndItsMarkdown() {
        let container = NSView()
        let note = NoteItem(id: 1, text: "pass: **rotate-me**", isPlainText: true)

        fixture.coordinator.setup(container: container, notes: [note], selectedIndex: 0)

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
        fixture.coordinator.setup(container: container, notes: notes, selectedIndex: 0)

        // Leave note 0, flip its mode while its view is off screen, then come back to it.
        fixture.coordinator.update(notes: notes, selectedIndex: 1)
        notes[0].isPlainText = true
        fixture.coordinator.update(notes: notes, selectedIndex: 0)

        let scrollView = try #require(container.subviews.first as? NSScrollView)
        let textView = try #require(scrollView.documentView as? MarkdownTextView)
        let storage = try #require(textView.textStorage)
        #expect(
            storage.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
                == fixture.baseFont(plainText: true))
    }

    // MARK: - Switching, in both directions

    /// The bug this fix exists for, in its second form: switching modes used to clear the
    /// note's formatting for good. Now each mode is a shape of the same note, and the switch
    /// converts between them.
    @Test(.bug(id: 117))
    func switchingModesAndBackRestoresTheStyling() throws {
        let textView = try fixture.textView()
        fixture.configure(plainText: false)
        textView.load(markdown: "pass: **rotate-me**")

        let styled = try fixture.font(at: 8)
        try #require(styled.isBold)

        fixture.configure(plainText: true)
        #expect(textView.string == "pass: **rotate-me**", "Plain mode shows the source")
        #expect(try fixture.font(at: 8) == fixture.baseFont(plainText: true), "and styles none of it")

        fixture.configure(plainText: false)
        #expect(textView.string == "pass: rotate-me", "Formatted mode draws it again")
        #expect(try fixture.font(at: 8) == styled)
        #expect(textView.markdown == "pass: **rotate-me**", "and the note is what it always was")
    }

    /// Repeatedly, not just once. Each switch is a conversion, so a note that lost or gained a
    /// character on the way through would drift a little further with every flip — which is the
    /// one failure mode this design has that drawing the source did not.
    @Test(.bug(id: 124)) func switchingModesIsReversibleIndefinitely() throws {
        let textView = try fixture.textView()
        let source = "- [ ] rotate ~~the~~ *keys*"
        fixture.configure(plainText: false)
        textView.load(markdown: source)

        for _ in 0..<5 {
            fixture.configure(plainText: true)
            fixture.configure(plainText: false)
        }

        #expect(textView.markdown == source, "Five round trips, character for character")

        // "- [ ] rotate the *keys*" — `*keys*` is literal, since italic is spelled `_`.
        #expect(textView.string == "- [ ] rotate the *keys*")
        let storage = try #require(textView.textStorage)
        #expect(
            storage.attribute(.strikethroughStyle, at: 13, effectiveRange: nil) as? Int
                == NSUnderlineStyle.single.rawValue)
    }

    /// `configure` runs on every update and is a repaint, so running it twice has to land in the
    /// same place. It no longer needs a guard against that — under the old implementation an
    /// unguarded second call re-flattened the note.
    @Test func configuringTwiceLeavesTheSameResult() throws {
        let textView = try fixture.textView()
        textView.string = "**bold**"

        fixture.configure(plainText: false)
        let once = try fixture.font(at: 2)
        fixture.configure(plainText: false)

        #expect(try fixture.font(at: 2) == once)
        #expect(textView.string == "**bold**")
    }

    // MARK: - Paste

    /// Styled text arriving from another app lands as characters, in the note's own font.
    ///
    /// Read from a private pasteboard rather than `paste(_:)`, which would take over the user's
    /// real clipboard for the length of the run. This is the raw AppKit read — the path that used
    /// to leave attributes behind — so it proves normalizing erases them wherever they enter.
    @Test func pastingStyledTextIntoAPlainNoteDropsTheStyling() throws {
        let textView = try fixture.textView()
        fixture.configure(plainText: true)

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

        #expect(textView.string == "rotate-me")
        #expect(
            try fixture.font(at: 0) == fixture.baseFont(plainText: true),
            "The pasted run takes the note's own font, not the source app's")

        let storage = try #require(textView.textStorage)
        #expect(
            storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
                == .adaptiveEditorText,
            "and the note's own colour")
    }

    // MARK: - Formatting shortcuts

    /// ⌘B, ⌘I and ⌘⇧X have nothing to apply in a note that shows its source: the only thing they
    /// could do there is type delimiters the user is already free to type.
    @Test func formattingShortcutsDoNothingInAPlainNote() throws {
        let textView = try fixture.textView()
        fixture.configure(plainText: true)
        textView.load(markdown: "user: admin")
        textView.setSelectedRange(NSRange(location: 0, length: 4))

        manager.toggleEmphasis(.strong, on: textView)
        manager.toggleEmphasis(.emphasis, on: textView)
        manager.toggleStrikethrough(on: textView)

        #expect(textView.string == "user: admin")
    }

    /// The same commands still work in a rich note — the guard is on the mode, not on the
    /// commands. `EditorFormattingTests` covers what they do in detail.
    @Test func formattingShortcutsStillWorkInARichNote() throws {
        let textView = try fixture.textView()
        fixture.configure(plainText: false)
        textView.load(markdown: "user: admin")
        textView.setSelectedRange(NSRange(location: 0, length: 4))

        manager.toggleEmphasis(.strong, on: textView)

        #expect(textView.markdown == "**user**: admin")
    }

    // MARK: - Pasting

    /// ⌘V follows the same guard the formatting commands do. Converting a pasted bold run to
    /// `**secret**` in a note where ⌘B is silenced would put delimiters in it that none of its
    /// own commands could take back out — the one thing the whole Markdown swap exists to stop.
    @Test func pastingIntoAPlainNoteBringsNoDelimiters() throws {
        let textView = try fixture.textView()
        fixture.configure(plainText: true)
        textView.load(markdown: "")

        let scratch = ScratchPasteboard()
        scratch.write { $0.setData(Data("<b>secret</b>".utf8), forType: .html) }
        let shortcutManager = EditorShortcutManager(
            defaults: scratchDefaults.defaults, pasteboard: scratch.pasteboard)

        shortcutManager.pasteAsMarkdown(on: textView)

        #expect(textView.string == "secret")
    }

    /// The same clipboard in a rich note keeps the bold — as bold on screen, and as `**` in what
    /// the note stores.
    @Test(.bug(id: 124)) func pastingIntoARichNoteKeepsTheFormatting() throws {
        let textView = try fixture.textView()
        fixture.configure(plainText: false)
        textView.load(markdown: "")

        let scratch = ScratchPasteboard()
        scratch.write { $0.setData(Data("<b>secret</b>".utf8), forType: .html) }
        let shortcutManager = EditorShortcutManager(
            defaults: scratchDefaults.defaults, pasteboard: scratch.pasteboard)

        shortcutManager.pasteAsMarkdown(on: textView)

        #expect(textView.string == "secret", "No delimiters land in the buffer")
        #expect(textView.markdown == "**secret**")
    }
}
