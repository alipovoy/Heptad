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

    init() throws {
        fixture = try MarkdownEditorFixture()
    }

    // MARK: - Repainting

    /// An edit repaints the lines it landed on, not the whole note — a construct never spans
    /// lines, so nothing further can have changed. The result has to be indistinguishable from
    /// repainting everything, which is what this compares it against.
    @Test func editingOneLineRepaintsItToTheSameResultAsRepaintingAll() throws {
        let textView = try fixture.textView()
        fixture.configure(plainText: false)
        textView.string = "**one**\nplain here\n_three_"
        textView.restyle()

        let storage = try #require(textView.textStorage)
        storage.replaceCharacters(in: NSRange(location: 8, length: 10), with: "~~struck~~")

        let afterEdit = NSAttributedString(attributedString: storage)
        textView.restyle()

        #expect(
            afterEdit.isEqual(to: storage),
            "The line-scoped repaint left the note as a full one would")
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

        // And so does the formatting, which is the half that used to survive.
        #expect(
            textView.typingAttributes[.font] as? NSFont == fixture.baseFont(plainText: false),
            "Typing after the undo is the note's own font, not the clipboard's")
        #expect(textView.typingAttributes[.foregroundColor] as? NSColor == .adaptiveEditorText)
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
        textView.string = "**keys** and _more_"
        fixture.configure(plainText: false)
        textView.setSelectedRange(NSRange(location: 0, length: 19))

        // No rich flavor offered, and the plain one still spelled the way AppKit's own writer
        // recognises — returning `[.string]` here makes `writeSelection` fail and copy nothing.
        #expect(textView.writablePasteboardTypes.isEmpty == false)
        #expect(textView.writablePasteboardTypes.allSatisfy { $0 != .rtf && $0 != .rtfd })

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
