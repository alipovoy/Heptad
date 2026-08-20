import AppKit

/// A note's markdown as RTF: what ⌘⇧C leaves for Mail, Word and anything else that reads rich
/// text.
///
/// The one thing ⌘C deliberately cannot do. That command writes the note's own characters, which
/// is what keeps a copy from one note into another exact — see `MarkdownTextView`. This is the
/// other direction, out of the app, where the delimiters are noise and the formatting is the
/// point.
///
/// Rendered the way `RichTextRendering` renders it and then made neutral: how a note is *drawn* is
/// this app's business, and the receiving document has its own body colour and its own idea of how
/// big text is.
enum RichTextExport {
    /// `markdown` rendered and serialized, or nil when there is nothing to write — which leaves
    /// the caller's clipboard alone rather than emptying it.
    static func rtf(from markdown: String) -> Data? {
        let rich = NSMutableAttributedString(
            attributedString: RichTextRendering.attributed(from: markdown, appearance: exporting))
        let whole = NSRange(location: 0, length: rich.length)
        guard whole.length > 0 else { return nil }

        uncolour(rich, over: whole)

        return try? rich.data(
            from: whole, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }

    /// Takes the body colour off every run but a link's, so those runs are written `\cf0` — the
    /// RTF spelling of "the document's own colour".
    ///
    /// Left on, the note would arrive pinned to black: AppKit resolves `adaptiveEditorText` and
    /// writes it into the colour table as literal RGB, whichever appearance the app is in. Black
    /// is right for a white page and wrong for every dark-themed destination, and neither is this
    /// app's call to make.
    ///
    /// A link keeps what it arrived with. Its colour is the signal that it is a link, and RTF
    /// carries `linkColor` as a system colour the destination resolves for itself.
    private static func uncolour(_ rich: NSMutableAttributedString, over range: NSRange) {
        var plain: [NSRange] = []

        // Collected before anything is written, for the reason `MarkdownStyling.normalize` gives:
        // removing an attribute splits the runs being enumerated.
        rich.enumerateAttributes(in: range, options: []) { attributes, subrange, _ in
            guard attributes[.link] == nil else { return }
            plain.append(subrange)
        }

        for subrange in plain {
            rich.removeAttribute(.foregroundColor, range: subrange)
        }
    }

    /// No note tint, and the default size rather than `EditorFontSize.current`: the zoom is how
    /// this window is read, not how big the text is, and a pasted paragraph should not carry one
    /// app's magnification into another.
    private static let exporting = MarkdownStyling.Appearance(
        plainText: false, fontSize: AppConstants.Layout.defaultFontSize, tintedNoteIndex: nil)
}
