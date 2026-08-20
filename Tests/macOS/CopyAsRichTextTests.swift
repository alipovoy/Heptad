import AppKit
import Testing

@testable import Heptad

/// What ⌘C, ⌘X and a drag out of a note leave on the clipboard: RTF for a document that draws
/// formatting, the note's markdown for anything that takes text, and a private flavor this app
/// reads back verbatim.
///
/// Beside `MarkdownTextViewTests` rather than in it, for the reason `MarkdownReadback` sits beside
/// `MarkdownWriting`: the two together no longer fit under the 400-line ceiling `swiftlint` holds
/// this project to.
///
/// The RTF is read back through `NSAttributedString`, which is what the receiving app does.
/// Asserting on the bytes would pin AppKit's spelling of the same thing.
@MainActor
struct CopyAsRichTextTests {
    private let fixture: MarkdownEditorFixture

    init() throws {
        fixture = try MarkdownEditorFixture()
    }

    // MARK: - Fixtures

    /// Copies the whole note the way `copy(_:)` does — declaring the view's own types, then asking
    /// it to fill each one in.
    @discardableResult
    private func copyAll(
        of markdown: String, plainText: Bool = false,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> ScratchPasteboard {
        fixture.configure(plainText: plainText)
        let textView = try fixture.textView(sourceLocation: sourceLocation)
        textView.load(markdown: markdown)
        textView.setSelectedRange(NSRange(location: 0, length: (textView.string as NSString).length))

        let scratch = ScratchPasteboard()
        scratch.pasteboard.declareTypes(textView.writablePasteboardTypes, owner: nil)
        #expect(
            textView.writeSelection(
                to: scratch.pasteboard, types: textView.writablePasteboardTypes),
            sourceLocation: sourceLocation)

        return scratch
    }

    private func decoded(
        _ scratch: ScratchPasteboard, sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> NSAttributedString {
        let rtf = try #require(scratch.pasteboard.data(forType: .rtf), sourceLocation: sourceLocation)

        return try NSAttributedString(
            data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil)
    }

    // MARK: - The flavors offered

    /// Three flavors, so the destination picks rather than this app guessing which one it wanted.
    @Test func aFormattedNoteOffersRichTextAndTwoSpellingsOfTheSource() throws {
        let scratch = try copyAll(of: "rotate **keys**")

        #expect(scratch.pasteboard.data(forType: .rtf) != nil)
        #expect(scratch.pasteboard.string(forType: .heptadMarkdown) == "rotate **keys**")
        #expect(scratch.pasteboard.string(forType: .string) == "rotate **keys**")
    }

    /// A plain-text note has no formatting to carry, so the rich flavors would be the same
    /// characters at more expense. The text is still the note's own.
    @Test func aPlainTextNoteOffersItsCharactersAndNothingElse() throws {
        let scratch = try copyAll(of: "rotate **keys**", plainText: true)

        #expect(scratch.pasteboard.data(forType: .rtf) == nil)
        #expect(scratch.pasteboard.string(forType: .heptadMarkdown) == nil)
        #expect(scratch.pasteboard.string(forType: .string) == "rotate **keys**")
    }

    /// The guarantee the private flavor exists for. ⌘V prefers rich flavors, so without it a copy
    /// from one note into another would go out through `RichTextExport` and back through
    /// `MarkdownWriting` — inverse on everything tried, but a conversion where there was none.
    ///
    /// The escaped asterisks are the case that makes it worth pinning: they are the note saying
    /// "these are characters", which only the source spelling carries.
    @Test(
        arguments: [
            "rotate **keys**", "**_both_**", "the **_hard_**ware",
            "**x** a \\*b\\* c", "see [docs](https://example.com) first",
            "- [ ] rotate **keys**\n- [x] done", "a 🔑 **key**"
        ])
    func copyingIntoAnotherNoteConvertsNothing(markdown: String) throws {
        let scratch = try copyAll(of: markdown)

        #expect(scratch.pasteboard.markdownForPaste() == markdown)
    }

    /// Nothing selected has no RTF to write, so the flavor is absent rather than an empty
    /// document. `writeSelection(to:types:)` still succeeds on the text flavors.
    @Test func anEmptySelectionWritesNoRichFlavor() throws {
        fixture.configure(plainText: false)
        let textView = try fixture.textView()
        textView.load(markdown: "rotate **keys**")
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        let scratch = ScratchPasteboard()
        scratch.pasteboard.declareTypes(textView.writablePasteboardTypes, owner: nil)
        _ = textView.writeSelection(to: scratch.pasteboard, types: textView.writablePasteboardTypes)

        #expect(scratch.pasteboard.data(forType: .rtf) == nil)
    }

    // MARK: - The vocabulary that travels

    /// The four constructs with a markdown spelling are the four that survive. The delimiters do
    /// not: this is the direction where they are noise.
    @Test func theVocabularyArrivesAsFormattingRatherThanDelimiters() throws {
        let rich = try decoded(try copyAll(of: "**bold** _italic_ ~~struck~~"))

        #expect(rich.string == "bold italic struck")
        #expect(rich.carrying(.strong) == "####..............")
        #expect(rich.carrying(.emphasis) == ".....######.......")
        #expect(rich.carrying(.strikethrough) == "............######")
    }

    @Test func aLinkKeepsItsDestination() throws {
        let rich = try decoded(try copyAll(of: "see [docs](https://example.com) first"))

        #expect(rich.string == "see docs first")
        #expect(
            MarkdownWriting.destination(rich.attribute(.link, at: 4, effectiveRange: nil))
                == "https://example.com")
    }

    /// A bullet is content, so it travels as the characters it is. RTF list structure is not
    /// something this app has a spelling for in either direction.
    @Test func listMarkersTravelAsCharacters() throws {
        #expect(try decoded(try copyAll(of: "- [ ] rotate **keys**")).string == "- [ ] rotate keys")
    }

    // MARK: - What is deliberately left behind

    /// The note's own colours stay in the note. An ordinary run is written `\cf0` — the RTF
    /// spelling of "the document's own colour" — so a paste takes the destination's body colour
    /// rather than arriving pinned to this app's.
    ///
    /// Bold is the case worth naming: on screen it is drawn in the note's tint, and carrying one
    /// note's colour into an unrelated document would be nonsense.
    @Test func noRunCarriesTheNotesOwnColour() throws {
        let rich = try decoded(try copyAll(of: "**bold** and plain"))

        for location in 0..<rich.length {
            #expect(
                rich.attribute(.foregroundColor, at: location, effectiveRange: nil) == nil,
                "at \(location)")
        }
    }

    /// A link is the exception, because its colour is the signal: text that stopped looking like a
    /// link would arrive as ordinary words with a destination nobody can see.
    @Test func aLinkKeepsItsColour() throws {
        let rich = try decoded(try copyAll(of: "see [docs](https://example.com)"))

        #expect(rich.attribute(.foregroundColor, at: 4, effectiveRange: nil) != nil)
        #expect(rich.attribute(.foregroundColor, at: 0, effectiveRange: nil) == nil)
    }

    /// The editor's zoom is how this window is read, not how big the text is.
    @Test func theExportIsAtTheDefaultSizeRatherThanTheAppsZoom() throws {
        let rich = try decoded(try copyAll(of: "plain"))
        let font = try #require(rich.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)

        #expect(font.pointSize == AppConstants.Layout.defaultFontSize)
    }

    @Test func thereIsNothingToWriteForEmptyMarkdown() {
        #expect(RichTextExport.rtf(from: "") == nil)
    }
}
