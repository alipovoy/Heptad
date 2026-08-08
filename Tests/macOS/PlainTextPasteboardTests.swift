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
@Suite struct PlainTextPasteboardTests {
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
}
