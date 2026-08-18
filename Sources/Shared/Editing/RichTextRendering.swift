import Foundation

#if canImport(UIKit)
    import UIKit
#else
    import AppKit
#endif

/// Markdown source in, what the user sees out.
///
/// This is half of the mode switch (#124). A note is stored as markdown, but in formatted mode
/// the editor holds *rich text* — bold is a bold font, not two asterisks the caret has to be kept
/// out of. The delimiters are not hidden here; they are gone, and `MarkdownWriting` puts them
/// back when the note is saved or the mode is switched.
///
/// Dropping them rather than concealing them is what makes the whole class of editing bug go
/// away: there is nothing invisible in the buffer for an arrow key to stall on, for a backspace
/// to break in half, or for `⌘B` to nest in the wrong order.
enum RichTextRendering {
    /// The note as the editor should hold it in `appearance`'s mode.
    ///
    /// Plain mode gets the source verbatim, in one monospaced font: that mode exists to show the
    /// characters, so it parses nothing.
    static func attributed(
        from markdown: String, appearance: MarkdownStyling.Appearance
    ) -> NSAttributedString {
        let base = MarkdownStyling.baseAttributes(appearance)
        guard appearance.isStyled else {
            return NSAttributedString(string: markdown, attributes: base)
        }

        let source = markdown as NSString
        let spans = MarkdownSyntax.spans(in: source)
        let hidden = spans.filter { $0.style == .marker }.map(\.range)

        let rendered = NSMutableAttributedString(
            string: text(of: source, without: hidden), attributes: base)

        for span in spans where span.style != .marker {
            let range = map(span.range, past: hidden)
            guard range.length > 0, NSMaxRange(range) <= rendered.length else { continue }

            apply(span, over: range, to: rendered, in: source, spans: spans)
        }

        // The tint last, over the finished runs, and skipping links. Spans arrive in parse order,
        // so a bold span and the link span enclosing it can land either way round — this is what
        // keeps which one wins from depending on that order. The link colour above is applied as
        // the span is, and stands.
        MarkdownStyling.tintBold(appearance, in: rendered)

        return rendered
    }

    // MARK: - Dropping the delimiters

    /// `source` with every hidden range cut out of it.
    private static func text(of source: NSString, without hidden: [NSRange]) -> String {
        var kept = ""
        var cursor = 0

        for range in hidden.sorted(by: { $0.location < $1.location }) {
            guard range.location >= cursor else { continue }
            kept += source.substring(with: NSRange(location: cursor, length: range.location - cursor))
            cursor = NSMaxRange(range)
        }

        kept += source.substring(from: min(cursor, source.length))
        return kept
    }

    /// `range` in source coordinates, moved to where it lands once the hidden runs are gone.
    ///
    /// Both ends are mapped independently, so a range with markers *inside* it — the content of
    /// `**_keys_**` holds the italic pair — comes back shortened by exactly what was dropped.
    private static func map(_ range: NSRange, past hidden: [NSRange]) -> NSRange {
        let start = index(range.location, past: hidden)
        let end = index(NSMaxRange(range), past: hidden)
        return NSRange(location: start, length: max(0, end - start))
    }

    private static func index(_ index: Int, past hidden: [NSRange]) -> Int {
        let dropped = hidden.reduce(0) { total, range in
            guard range.location < index else { return total }
            return total + min(range.length, index - range.location)
        }
        return index - dropped
    }

    // MARK: - Drawing what is left

    private static func apply(
        _ span: MarkdownSyntax.Span, over range: NSRange, to rendered: NSMutableAttributedString,
        in source: NSString, spans: [MarkdownSyntax.Span]
    ) {
        switch span.style {
        case .strong:
            MarkdownStyling.restyle(rendered, over: range) { $0.bolded() }
        case .emphasis:
            MarkdownStyling.restyle(rendered, over: range) { $0.italicized() }
        case .strikethrough:
            rendered.addAttribute(
                .strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        case .link:
            rendered.addAttribute(.foregroundColor, value: PlatformColor.editorLink, range: range)
            rendered.addAttribute(
                .underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)

            // The destination lives in the marker the parser left just after the label, which is
            // the whole of `](https://…)`. Carried as an attribute because it is the one part of
            // a link that formatted mode does not draw — and `MarkdownWriting` needs it back.
            if let url = destination(afterLabelEndingAt: NSMaxRange(span.range), in: source,
                                     spans: spans) {
                rendered.addAttribute(.link, value: url, range: range)
            }
        case .marker, .listMarker:
            // Markers are gone by now, and a bullet is content the base attributes already drew.
            break
        }
    }

    /// The URL out of the `](https://…)` marker that closes a link.
    private static func destination(
        afterLabelEndingAt end: Int, in source: NSString, spans: [MarkdownSyntax.Span]
    ) -> String? {
        guard
            let marker = spans.first(where: { $0.style == .marker && $0.range.location == end })
        else { return nil }

        let text = source.substring(with: marker.range)
        guard text.hasPrefix("]("), text.hasSuffix(")") else { return nil }
        return String(text.dropFirst(2).dropLast())
    }
}
