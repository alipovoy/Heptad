import AppKit
import Testing

@testable import Heptad

private enum PlainTextPasteboardTestError: Error {
    case unhandledFlavor(String)
}

/// What ⌘⇧V is willing to read, flavor by flavor.
///
/// The suite exists because `NSTextView.pasteAsPlainText` read exactly one of them and came back
/// empty on every clipboard below that lacks it, while ⌘V pasted the same clipboards fine (#114).
/// Each case is one of those clipboards.
struct PlainTextPasteboardTests {
    /// Bold, so a case can tell "the rich flavor was decoded" from "some plain flavor was
    /// already there" — only the characters ever survive this call.
    private static let formatted = NSAttributedString(
        string: "formatted", attributes: [.font: NSFont.boldSystemFont(ofSize: 18)])

    /// Named by string rather than by an enum for the reason `EditorShortcutManagerTests` gives:
    /// a private type in a parameterized test's signature would force the test itself private.
    private static func data(for flavor: String) throws -> (NSPasteboard.PasteboardType, Data) {
        let range = NSRange(location: 0, length: formatted.length)
        switch flavor {
        case "html":
            return (.html, Data("<b>formatted</b>".utf8))
        case "rtfd":
            return (.rtfd, try #require(formatted.rtfd(from: range, documentAttributes: [:])))
        default:
            throw PlainTextPasteboardTestError.unhandledFlavor(flavor)
        }
    }

    private static func rtf() throws -> Data {
        let range = NSRange(location: 0, length: formatted.length)
        return try #require(formatted.rtf(from: range, documentAttributes: [:]))
    }

    // MARK: - Flavors

    @Test func aPlainTextFlavorIsTakenAsIs() {
        let scratch = ScratchPasteboard()
        scratch.write { $0.setString("copied", forType: .string) }

        #expect(scratch.pasteboard.plainTextForPaste() == "copied")
    }

    /// RTF is deliberately not among these: the pasteboard translates that one to plain text on
    /// its own, which is why ⌘⇧V worked often enough for the bug to read as intermittent.
    @Test(arguments: ["html", "rtfd"])
    func aRichFlavorWithNoPlainTextAlongsideItIsFlattened(flavor: String) throws {
        let (type, data) = try Self.data(for: flavor)
        let scratch = ScratchPasteboard()
        scratch.write { $0.setData(data, forType: type) }

        #expect(scratch.pasteboard.plainTextForPaste() == "formatted")
    }

    /// The case a `types.contains(.string)` guard waves through: the flavor is declared, and the
    /// data behind it is empty. Falling through to the rich flavor is what saves the paste.
    @Test func anEmptyPlainTextFlavorFallsThroughToTheRichOne() throws {
        let rtf = try Self.rtf()
        let scratch = ScratchPasteboard()
        scratch.write {
            $0.setData(rtf, forType: .rtf)
            $0.setString("", forType: .string)
        }

        #expect(scratch.pasteboard.plainTextForPaste() == "formatted")
    }

    /// A file URL pastes as its path rather than its `file://` spelling — matching ⌘V, and the
    /// only one of the two worth reading in a note.
    @Test(
        arguments: [
            (NSPasteboard.PasteboardType.fileURL, "file:///etc/hosts", "/etc/hosts"),
            (.URL, "https://example.com", "https://example.com")
        ])
    func aURLPastesAsText(
        type: NSPasteboard.PasteboardType, written: String, expected: String
    ) {
        let scratch = ScratchPasteboard()
        scratch.write { $0.setString(written, forType: type) }

        #expect(scratch.pasteboard.plainTextForPaste() == expected)
    }

    /// What the clipboard carries that a note may not hold is dropped on the way in, on every
    /// flavor — ⌘⇧V never goes near the writer, so this reading is the only place to do it.
    /// U+FFFC is what an image on the clipboard contributes to the text beside it.
    @Test(arguments: [("secret\u{FFFC}", "secret"), ("a\u{0}b", "ab"), ("a\r\nb", "a\nb")])
    func charactersANoteMayNotHoldAreDropped(written: String, expected: String) {
        let scratch = ScratchPasteboard()
        scratch.write { $0.setString(written, forType: .string) }

        #expect(scratch.pasteboard.plainTextForPaste() == expected)
    }

    /// A flavor holding nothing but those characters is an empty flavor, so the search falls
    /// through to one with text in it rather than pasting nothing.
    @Test func aFlavorOfNothingButThoseCharactersFallsThrough() throws {
        let rtf = try Self.rtf()
        let scratch = ScratchPasteboard()
        scratch.write {
            $0.setData(rtf, forType: .rtf)
            $0.setString("\u{FFFC}", forType: .string)
        }

        #expect(scratch.pasteboard.plainTextForPaste() == "formatted")
    }

    /// nil, not "", so the caller can tell a clipboard with no text from one holding empty text
    /// — the first leaves the note alone, and only the second would be a paste of nothing.
    @Test func aClipboardHoldingNoTextIsNil() throws {
        let scratch = ScratchPasteboard()
        try scratch.writeAnImage()

        #expect(scratch.pasteboard.plainTextForPaste() == nil)
    }

    /// Every item, not just the first: a multi-file copy that pasted one path would lose the rest
    /// silently, which is the failure this whole issue was about.
    @Test func multipleItemsPasteAsMultipleLines() {
        let scratch = ScratchPasteboard()
        scratch.pasteboard.clearContents()
        let items = ["one", "two"].map { text -> NSPasteboardItem in
            let item = NSPasteboardItem()
            item.setString(text, forType: .string)
            return item
        }
        scratch.pasteboard.writeObjects(items)

        #expect(scratch.pasteboard.plainTextForPaste() == "one\ntwo")
    }

    // MARK: - Converting a paste to Markdown

    /// Runs are split by *any* attribute change, not only the ones with a Markdown spelling. A
    /// bold phrase with one word in another colour arrived as three runs and came out as three
    /// delimiter pairs — `**rotate **` `**keys**` `** now**` — which reads back as literal
    /// asterisks, since a pair cannot close against a space. One phrase is one pair.
    @Test func adjacentRunsSpellingTheSameMarkdownBecomeOnePair() {
        let styled = NSMutableAttributedString(
            string: "rotate keys now", attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
        styled.addAttribute(
            .foregroundColor, value: NSColor.systemRed, range: NSRange(location: 7, length: 4))

        #expect(styled.markdownRepresentation() == "**rotate keys now**")
    }

    /// A snippet that contains delimiters of its own arrives as those characters, not as
    /// formatting nobody applied — the paste is written through the same escaping writer a save
    /// goes through.
    @Test(.bug(id: 124)) func delimitersInsideAPastedRunAreEscaped() throws {
        let styled = NSAttributedString(
            string: "run **build** now", attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])

        // Asserted by reading it back rather than by its spelling: what matters is that the note
        // ends up holding the snippet, bold, with its asterisks still asterisks.
        let read = RichTextRendering.attributed(
            from: styled.markdownRepresentation(),
            appearance: MarkdownStyling.Appearance(
                plainText: false, fontSize: AppConstants.Layout.defaultFontSize))

        #expect(read.string == "run **build** now")
        let font = try #require(read.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(font.isBold)
    }

    /// A clipboard of bare characters is text already — markdown someone wrote by hand, or a
    /// note copied out of this app — so ⌘V reads it as the source it looks like rather than
    /// escaping the delimiters it meant.
    @Test(.bug(id: 124)) func anUnformattedClipboardIsNotRewritten() {
        let scratch = ScratchPasteboard()
        scratch.write { $0.setString("**keys** and _more_", forType: .string) }

        #expect(scratch.pasteboard.markdownForPaste() == "**keys** and _more_")
    }

    /// The delimiters go around the run's content, not around the run: `**bold **` is four
    /// literal asterisks that no command could then remove.
    @Test func whitespaceStaysOutsideTheDelimiters() {
        let styled = NSMutableAttributedString(string: "rotate keys now")
        styled.addAttribute(
            .font, value: NSFont.boldSystemFont(ofSize: 13), range: NSRange(location: 6, length: 6))

        #expect(styled.markdownRepresentation() == "rotate **keys** now")
    }

    /// A construct never spans lines, so a bold run that crosses one is wrapped line by line.
    @Test func aRunCrossingALineIsWrappedOnEachLine() {
        let styled = NSAttributedString(
            string: "one\ntwo", attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])

        #expect(styled.markdownRepresentation() == "**one**\n**two**")
    }

    /// Italic is `_`, so a converted paste has to spell it that way or the note would hold
    /// asterisks that `⌘I` could never take off again.
    @Test func italicArrivesAsAnUnderscorePair() {
        let italic = NSFontManager.shared.convert(
            NSFont.systemFont(ofSize: 13), toHaveTrait: .italicFontMask)
        let styled = NSAttributedString(string: "keys", attributes: [.font: italic])

        #expect(styled.markdownRepresentation() == "_keys_")
    }

    // MARK: - Links
    //
    // The common rich paste: anything copied out of a browser carries one. Nothing else in the
    // conversion reaches `url(in:)`, so without these the whole link arm is unexercised.

    @Test func aLinkArrivesAsAMarkdownLink() throws {
        let url = try #require(URL(string: "https://example.com"))
        let styled = NSAttributedString(string: "docs", attributes: [.link: url])

        #expect(styled.markdownRepresentation() == "[docs](https://example.com)")
    }

    /// AppKit hands `.link` back as a `URL` from some sources and as a plain `String` from
    /// others, depending on which flavor decoded it — so both spellings have to read.
    @Test func aLinkStoredAsAStringReadsTheSameWay() {
        let styled = NSAttributedString(
            string: "docs", attributes: [.link: "https://example.com"])

        #expect(styled.markdownRepresentation() == "[docs](https://example.com)")
    }

    /// `MarkdownSyntax` does not parse inside a link's label, so emphasis over a link is written
    /// *around* it. That is a spelling the parser reads (`MarkdownSyntaxTests`
    /// `aLinkNestsButItsLabelIsNotParsed`), so the trait survives the save it used to be dropped
    /// by — and ⌘B can take it off again, which is the rule the whole conversion exists to hold.
    @Test func aBoldLinkKeepsBothTheLinkAndTheBold() throws {
        let url = try #require(URL(string: "https://example.com"))
        let styled = NSAttributedString(
            string: "docs",
            attributes: [.link: url, .font: NSFont.boldSystemFont(ofSize: 13)])

        #expect(styled.markdownRepresentation() == "**[docs](https://example.com)**")
    }

    /// The pair has to go around the whole link — the label is not parsed, so there is nowhere
    /// else to put it. A trait covering only part of one has no spelling and is dropped.
    @Test func boldOverPartOfALinkIsDropped() throws {
        let url = try #require(URL(string: "https://example.com"))
        let styled = NSMutableAttributedString(string: "docs", attributes: [.link: url])
        styled.addAttribute(
            .font, value: NSFont.boldSystemFont(ofSize: 13), range: NSRange(location: 0, length: 2))

        #expect(styled.markdownRepresentation() == "[docs](https://example.com)")
    }

    /// The other half of that rule, and the one a spelling change would break silently: what the
    /// conversion writes has to be what the parser reads back as a link.
    @Test func aConvertedLinkParsesBackAsALink() throws {
        let url = try #require(URL(string: "https://example.com"))
        let markdown = NSAttributedString(string: "docs", attributes: [.link: url])
            .markdownRepresentation()

        let spans = MarkdownSyntax.spans(in: markdown as NSString)

        #expect(spans.contains { $0.style == .link })
    }

    // MARK: - What ⌘V reads

    /// With nothing rich on the clipboard the markdown reading falls through to the plain one,
    /// which is what makes ⌘V work on an ordinary copy out of a terminal.
    @Test func markdownForPasteFallsBackToThePlainReading() {
        let scratch = ScratchPasteboard()
        scratch.write { $0.setString("rotate keys", forType: .string) }

        #expect(scratch.pasteboard.markdownForPaste() == "rotate keys")
    }

    /// nil rather than "", for the same reason as the plain reading: the caller leaves the note
    /// alone instead of pasting nothing over the selection.
    @Test func markdownForPasteIsNilForAClipboardHoldingNoText() throws {
        let scratch = ScratchPasteboard()
        try scratch.writeAnImage()

        #expect(scratch.pasteboard.markdownForPaste() == nil)
    }

    /// Past the size limit ⌘V stops decoding the markup and pastes the characters instead.
    ///
    /// The decode runs on the main thread inside the key-event monitor and is super-linear —
    /// 203 KB of HTML measured at 2.9 s, which is where macOS starts calling an app unresponsive.
    /// Losing the bold on a clipboard nobody would paste into a scratchpad is the better trade.
    @Test func anEnormousRichClipboardIsPastedAsItsCharacters() {
        let scratch = ScratchPasteboard()
        // `<b>keys</b> ` is 12 bytes, so this clears the limit with room to spare — and has to,
        // because a clipboard that reaches the decode at this size is what the test would hang on.
        let repeats = NSPasteboard.richPasteByteLimit / 8
        scratch.write {
            $0.setData(Data(String(repeating: "<b>keys</b> ", count: repeats).utf8), forType: .html)
            $0.setString(String(repeating: "keys ", count: repeats), forType: .string)
        }

        let pasted = scratch.pasteboard.markdownForPaste()

        #expect(pasted?.contains("**") == false, "The markup was not decoded")
        #expect(pasted?.hasPrefix("keys keys") == true, "and the characters came through")
    }

    /// The same clipboard under the limit keeps its formatting, so the guard above is a size
    /// check and not a second answer to "does this clipboard carry formatting".
    @Test func aRichClipboardUnderTheLimitKeepsItsFormatting() {
        let scratch = ScratchPasteboard()
        scratch.write { $0.setData(Data("<b>keys</b>".utf8), forType: .html) }

        #expect(scratch.pasteboard.markdownForPaste() == "**keys**")
    }
}
