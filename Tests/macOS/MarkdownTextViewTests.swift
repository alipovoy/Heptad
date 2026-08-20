import AppKit
import Testing

@testable import Heptad

/// The editor's text view itself, independent of which mode a note is in: what it repaints after
/// an edit, what it leaves on the caret, and what it writes to the pasteboard.
///
/// `PlainTextModeTests` covers the mode these all run under; this is the behaviour that is the
/// same either way.
@MainActor
struct MarkdownTextViewTests {
    private let fixture: MarkdownEditorFixture

    /// ⌘B writes the zoom nowhere, but the manager reads it — a scratch suite keeps the real
    /// app's stored size out of it either way.
    private let scratch: ScratchDefaults

    init() throws {
        fixture = try MarkdownEditorFixture()
        scratch = try ScratchDefaults(name: "MarkdownTextViewTests")
    }

    // MARK: - Loading and writing back

    /// The note goes in as markdown and comes back out as markdown, with rich text in between —
    /// which is the whole of #124's redesign, seen from the view that holds it.
    @Test(.bug(id: 124)) func aNoteGoesInAndComesBackOutAsMarkdown() throws {
        let textView = try fixture.textView()
        fixture.configure(plainText: false)

        textView.load(markdown: "**one**\nplain here\n_three_")

        #expect(textView.string == "one\nplain here\nthree", "No delimiters in the buffer")
        #expect(textView.markdown == "**one**\nplain here\n_three_")
    }

    /// A construct never spans lines, so the writer cannot spell a trait on a terminator
    /// (`aRunAcrossLinesIsWrittenLineByLine`); the renderer must not draw one either, or the buffer
    /// would claim formatting the next save is bound to drop.
    @Test func aReloadedNoteCarriesNoTraitOnItsLineTerminators() throws {
        try fixture.loaded("**a**\n**b**")

        #expect(try fixture.font(at: 0).isBold)
        #expect(try fixture.font(at: 1).isBold == false, "the terminator between them is bare")
        #expect(try fixture.font(at: 2).isBold)
    }

    /// Typing is no longer a parse: an edit only has to arrive normalized, so what is typed into
    /// a note is in the note's own font whatever the caret was carrying.
    @Test func typingLandsInTheNotesOwnFont() throws {
        let textView = try fixture.textView()
        fixture.configure(plainText: false)
        textView.load(markdown: "**one**")

        textView.setSelectedRange(NSRange(location: 3, length: 0))
        textView.insertText(" two", replacementRange: NSRange(location: 3, length: 0))

        let font = try fixture.font(at: 4)
        #expect(font.pointSize == fixture.baseFont(plainText: false).pointSize)
        #expect(textView.markdown == "**one two**", "and inside the bold run, stays bold")
    }

    /// The whole path, end to end: an edit in the editor becomes markdown in the store.
    ///
    /// The one place the redesign could lose a note is here — the buffer holds rich text, so what
    /// is saved is what `MarkdownWriting` makes of it rather than what is on screen. Driven
    /// through the coordinator and its saver, then flushed the way hiding the window flushes.
    @Test(.bug(id: 124)) func editingANoteWritesMarkdownBackToTheStore() throws {
        let container = NSView()
        let note = NoteItem(id: 0, text: "rotate keys")
        fixture.coordinator.setup(container: container, notes: [note], selectedIndex: 0)

        let scrollView = try #require(container.subviews.first as? NSScrollView)
        let textView = try #require(scrollView.documentView as? MarkdownTextView)
        try #require(textView.string == "rotate keys")

        textView.setSelectedRange(NSRange(location: 7, length: 4))  // "keys"
        EditorShortcutManager(defaults: scratch.defaults).toggleEmphasis(.strong, on: textView)

        // What the window does on its way off screen, and what a debounce would do on its own.
        // On the fixture's own centre, so it reaches this coordinator's saver and no one else's.
        fixture.notificationCenter.post(name: .flushPendingSaves, object: nil)

        #expect(note.text == "rotate **keys**")
    }

    // MARK: - Typing attributes

    /// The reported symptom of #117, end to end: paste formatted text, press ⌘Z, and the text
    /// goes but the formatting stays — colour and alignment left in `typingAttributes`, where
    /// no command could reach them, so everything typed afterwards came out wearing them.
    ///
    /// Driven through the raw AppKit read rather than ⌘V, which no longer goes anywhere near
    /// `paste(_:)`. That is deliberate: this pins the *repair*, not the avoidance, so the note
    /// stays clean even if something else ever puts attributes into the view.
    @Test(.bug(id: 117), .tags(.windowServer))
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
        fixture.coordinator.setup(container: container, notes: [note], selectedIndex: 0)

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

        // And so does everything the clipboard brought that this app cannot write back out. The
        // bold is allowed to stay on the caret — it has a markdown spelling and ⌘B takes it off
        // again, which is exactly what "stranded" meant and no longer applies to it.
        let font = try #require(textView.typingAttributes[.font] as? NSFont)
        #expect(
            font.pointSize == fixture.baseFont(plainText: false).pointSize,
            "Typing after the undo is the note's own size, not the clipboard's")
        // The clipboard's red is gone. What is there instead is the note's bold tint, because the
        // caret is still bold — a colour this app derives from the note, not one it was handed.
        // Both sides unwrapped: two nil conversions would compare equal and mean nothing.
        let caretColor = try #require(textView.typingAttributes[.foregroundColor] as? NSColor)
        let drawn = try #require(caretColor.usingColorSpace(.sRGB))
        let tint = try #require(NotePalette.boldTint(forNoteIndex: 0).usingColorSpace(.sRGB))
        #expect(drawn == tint)
        #expect(textView.typingAttributes[.paragraphStyle] == nil, "No alignment is left behind")
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
        let textView = try fixture.textView()
        fixture.configure(plainText: false)
        textView.load(markdown: "**keys** and _more_")
        textView.setSelectedRange(NSRange(location: 0, length: (textView.string as NSString).length))

        // AppKit's own rich flavors stay filtered out: those write the *drawn* buffer, and #117
        // was that paint being read back as delimiters. The `.rtf` offered in their place is
        // `RichTextExport`'s, which carries the vocabulary and none of the drawing —
        // `CopyAsRichTextTests` pins what is in it.
        //
        // The plain flavors are still spelled the way AppKit's own writer recognises: returning
        // `[.string]` here makes `writeSelection` fail and copy nothing.
        #expect(textView.writablePasteboardTypes.isEmpty == false)
        #expect(textView.writablePasteboardTypes.allSatisfy { $0 != .rtfd })

        // `writeSelection(to:types:)` writes into types the caller has already declared, which
        // is what `copy(_:)` does for it.
        let scratch = ScratchPasteboard()
        scratch.pasteboard.declareTypes(textView.writablePasteboardTypes, owner: nil)
        #expect(
            textView.writeSelection(
                to: scratch.pasteboard, types: textView.writablePasteboardTypes))

        #expect(scratch.pasteboard.markdownForPaste() == "**keys** and _more_")
    }
}
