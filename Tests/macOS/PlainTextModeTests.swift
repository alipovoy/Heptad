import AppKit
import Testing

@testable import Heptad

/// Per-note plain-text mode, where it is applied: the text view the coordinator configures, and
/// the commands that have to stop working in it.
///
/// The mode is a rendering choice now, not a transform. It used to flatten the note's attributes,
/// which made switching a one-way trip that took the formatting with it — the second half of
/// #117. Most of what this suite pins is that switching changes *nothing* about the text.
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

    /// A rich note opens proportional, with its markdown drawn.
    @Test func aRichNoteOpensProportionalWithItsMarkdownStyled() throws {
        let container = NSView()
        let note = NoteItem(id: 1, text: "pass: **rotate-me**")

        fixture.coordinator.setup(container: container, notes: [note], selectedIndex: 0)

        let scrollView = try #require(container.subviews.first as? NSScrollView)
        let textView = try #require(scrollView.documentView as? MarkdownTextView)
        let storage = try #require(textView.textStorage)

        #expect(
            storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
                == fixture.baseFont(plainText: false), "Unstyled text takes the base font")

        // "pass: **rotate-me**" — location 8 is inside the delimited run.
        let inRun = try #require(storage.attribute(.font, at: 8, effectiveRange: nil) as? NSFont)
        #expect(NSFontManager.shared.traits(of: inRun).contains(.boldFontMask))
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
    /// note's formatting for good. Now the source is untouched and the styling comes back.
    @Test(.bug(id: 117))
    func switchingModesAndBackRestoresTheStyling() throws {
        let textView = try fixture.textView()
        textView.string = "pass: **rotate-me**"
        fixture.configure(plainText: false)

        let styled = try fixture.font(at: 8)
        try #require(NSFontManager.shared.traits(of: styled).contains(.boldFontMask))

        fixture.configure(plainText: true)
        #expect(try fixture.font(at: 8) == fixture.baseFont(plainText: true),
            "Plain mode stops styling it")
        #expect(textView.string == "pass: **rotate-me**", "and changes not one character")

        fixture.configure(plainText: false)
        #expect(try fixture.font(at: 8) == styled, "Switching back brings the styling back")
    }

    /// Repeatedly, not just once: the mode is derived from the note on every repaint, so there
    /// is no state to wear down. Under the old flattening implementation the second round trip
    /// had nothing left to restore.
    @Test func switchingModesIsReversibleIndefinitely() throws {
        let textView = try fixture.textView()
        textView.string = "- [ ] rotate ~~the~~ *keys*"

        for _ in 0..<5 {
            fixture.configure(plainText: true)
            fixture.configure(plainText: false)
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
    /// to leave attributes behind — so it proves the repaint erases them wherever they enter.
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
        textView.restyle()

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

    /// ⌘B, ⌘I and ⌘⇧X have nothing worth applying in a note that leaves its markdown literal —
    /// the delimiters would be noise with nothing to show for them.
    @Test func formattingShortcutsDoNothingInAPlainNote() throws {
        let textView = try fixture.textView()
        textView.string = "user: admin"
        fixture.configure(plainText: true)
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
        textView.string = "user: admin"
        fixture.configure(plainText: false)
        textView.setSelectedRange(NSRange(location: 0, length: 4))

        manager.toggleEmphasis(.strong, on: textView)

        #expect(textView.string == "**user**: admin")
    }

    // MARK: - Pasting

    /// ⌘V follows the same guard the formatting commands do. Converting a pasted bold run to
    /// `**secret**` in a note where ⌘B is silenced would put delimiters in it that none of its
    /// own commands could take back out — the one thing the whole Markdown swap exists to stop.
    @Test func pastingIntoAPlainNoteBringsNoDelimiters() throws {
        let textView = try fixture.textView()
        textView.string = ""
        fixture.configure(plainText: true)

        let scratch = ScratchPasteboard()
        scratch.write { $0.setData(Data("<b>secret</b>".utf8), forType: .html) }
        let shortcutManager = EditorShortcutManager(
            defaults: scratchDefaults.defaults, pasteboard: scratch.pasteboard)

        shortcutManager.pasteAsMarkdown(on: textView)

        #expect(textView.string == "secret")
    }

    /// The same clipboard in a rich note does keep the bold, as source.
    @Test func pastingIntoARichNoteConvertsTheFormatting() throws {
        let textView = try fixture.textView()
        textView.string = ""
        fixture.configure(plainText: false)

        let scratch = ScratchPasteboard()
        scratch.write { $0.setData(Data("<b>secret</b>".utf8), forType: .html) }
        let shortcutManager = EditorShortcutManager(
            defaults: scratchDefaults.defaults, pasteboard: scratch.pasteboard)

        shortcutManager.pasteAsMarkdown(on: textView)

        #expect(textView.string == "**secret**")
    }
}
