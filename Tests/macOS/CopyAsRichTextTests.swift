import AppKit
import Testing

@testable import Heptad

/// ⌘⇧C: what the command leaves on the clipboard, and what `RichTextExport` puts in it.
///
/// Beside `EditorShortcutManagerTests` rather than in it, for the reason `MarkdownReadback` sits
/// beside `MarkdownWriting`: the two together no longer fit under the 400-line ceiling
/// `swiftlint` holds this project to.
///
/// The RTF is read back through `NSAttributedString`, which is what the receiving app does.
/// Asserting on the bytes would pin AppKit's spelling of the same thing.
@MainActor
struct CopyAsRichTextTests {
    private let scratchDefaults: ScratchDefaults
    private let textView: SpyTextView

    private var defaults: UserDefaults { scratchDefaults.defaults }

    init() throws {
        scratchDefaults = try ScratchDefaults(name: "CopyAsRichTextTests")
        textView = SpyTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
    }

    // MARK: - Fixtures

    /// See `EditorShortcutManagerTests`: the table never inspects the event, so any key will do.
    private func passThroughEvent() throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                windowNumber: 0, context: nil, characters: "k", charactersIgnoringModifiers: "k",
                isARepeat: false, keyCode: 40))
    }

    private func decoded(
        _ rtf: Data, sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> NSAttributedString {
        try NSAttributedString(
            data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil)
    }

    private func exported(
        _ markdown: String, sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> NSAttributedString {
        try decoded(
            try #require(RichTextExport.rtf(from: markdown), sourceLocation: sourceLocation),
            sourceLocation: sourceLocation)
    }

    private func mode(plainText: Bool) {
        textView.apply(
            MarkdownStyling.Appearance(
                plainText: plainText, fontSize: AppConstants.Layout.defaultFontSize))
    }

    // MARK: - The command

    /// ⌘⇧C leaves both flavors: the RTF the command exists for, and the markdown ⌘C would have
    /// written, so an app reading only plain text gets the note rather than nothing.
    @Test func bothTheRichAndThePlainFlavorAreWritten() throws {
        let scratch = ScratchPasteboard()
        let manager = EditorShortcutManager(defaults: defaults, pasteboard: scratch.pasteboard)
        textView.load(markdown: "rotate **keys**")
        textView.setSelectedRange(NSRange(location: 0, length: 11))  // "rotate keys"

        let result = manager.handleTextViewShortcut(
            chars: "c", hasShift: true, on: textView, event: try passThroughEvent())

        #expect(result == nil, "A command that ran means the key was consumed")
        #expect(scratch.pasteboard.string(forType: .string) == "rotate **keys**")

        let rich = try decoded(try #require(scratch.pasteboard.data(forType: .rtf)))
        #expect(rich.string == "rotate keys")
        #expect(rich.carrying(.strong) == ".......####", "and the bold is bold, not two asterisks")
        #expect(textView.commands.isEmpty, "⌘⇧C never reaches NSTextView.copy")
    }

    /// A plain-text note has no formatting to carry, so ⌘⇧C is ⌘C there — the same reason ⌘V
    /// pastes characters in that mode. No rich flavor at all, rather than one carrying the
    /// delimiters as text.
    @Test func aPlainTextNoteCopiesItsCharacters() throws {
        let scratch = ScratchPasteboard()
        let manager = EditorShortcutManager(defaults: defaults, pasteboard: scratch.pasteboard)
        mode(plainText: true)
        textView.load(markdown: "rotate **keys**")
        textView.setSelectedRange(NSRange(location: 0, length: 15))

        let result = manager.handleTextViewShortcut(
            chars: "c", hasShift: true, on: textView, event: try passThroughEvent())

        #expect(result == nil)
        #expect(scratch.pasteboard.string(forType: .string) == "rotate **keys**")
        #expect(scratch.pasteboard.data(forType: .rtf) == nil)
    }

    /// Nothing selected leaves the clipboard alone. The key is still consumed, for the reason the
    /// paste cases give: it is this app's key either way.
    @Test(arguments: [false, true])
    func nothingSelectedLeavesTheClipboardAsItWas(plainText: Bool) throws {
        let scratch = ScratchPasteboard()
        scratch.write { $0.setString("untouched", forType: .string) }
        let manager = EditorShortcutManager(defaults: defaults, pasteboard: scratch.pasteboard)
        mode(plainText: plainText)
        textView.load(markdown: "rotate **keys**")
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        let result = manager.handleTextViewShortcut(
            chars: "c", hasShift: true, on: textView, event: try passThroughEvent())

        #expect(result == nil)
        #expect(scratch.pasteboard.string(forType: .string) == "untouched")
    }

    // MARK: - The vocabulary that travels

    /// The four constructs with a markdown spelling are the four that survive. The delimiters do
    /// not: this is the direction where they are noise.
    @Test func theVocabularyArrivesAsFormattingRatherThanDelimiters() throws {
        let rich = try exported("**bold** _italic_ ~~struck~~")

        #expect(rich.string == "bold italic struck")
        #expect(rich.carrying(.strong) == "####..............")
        #expect(rich.carrying(.emphasis) == ".....######.......")
        #expect(rich.carrying(.strikethrough) == "............######")
    }

    @Test func aLinkKeepsItsDestination() throws {
        let rich = try exported("see [docs](https://example.com) first")

        #expect(rich.string == "see docs first")
        #expect(
            MarkdownWriting.destination(rich.attribute(.link, at: 4, effectiveRange: nil))
                == "https://example.com")
    }

    /// A bullet is content, so it travels as the characters it is. RTF list structure is not
    /// something this app has a spelling for in either direction.
    @Test func listMarkersTravelAsCharacters() throws {
        #expect(try exported("- [ ] rotate **keys**").string == "- [ ] rotate keys")
    }

    // MARK: - What is deliberately left behind

    /// The note's own colours stay in the note. An ordinary run is written `\cf0` — the RTF
    /// spelling of "the document's own colour" — so a paste takes the destination's body colour
    /// rather than arriving pinned to this app's.
    ///
    /// Bold is the case worth naming: on screen it is drawn in the note's tint, and carrying one
    /// note's colour into an unrelated document would be nonsense.
    @Test func noRunCarriesTheNotesOwnColour() throws {
        let rich = try exported("**bold** and plain")

        for location in 0..<rich.length {
            #expect(
                rich.attribute(.foregroundColor, at: location, effectiveRange: nil) == nil,
                "at \(location)")
        }
    }

    /// A link is the exception, because its colour is the signal: text that stopped looking like a
    /// link would arrive as ordinary words with a destination nobody can see.
    @Test func aLinkKeepsItsColour() throws {
        let rich = try exported("see [docs](https://example.com)")

        #expect(rich.attribute(.foregroundColor, at: 4, effectiveRange: nil) != nil)
        #expect(rich.attribute(.foregroundColor, at: 0, effectiveRange: nil) == nil)
    }

    /// The editor's zoom is how this window is read, not how big the text is.
    @Test func theExportIsAtTheDefaultSizeRatherThanTheAppsZoom() throws {
        let rich = try exported("plain")
        let font = try #require(rich.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)

        #expect(font.pointSize == AppConstants.Layout.defaultFontSize)
    }

    /// Nothing to write means nothing written, which is what the empty-selection case above rests
    /// on: ⌘⇧C cannot empty the clipboard.
    @Test func thereIsNothingToWriteForEmptyMarkdown() {
        #expect(RichTextExport.rtf(from: "") == nil)
    }
}
