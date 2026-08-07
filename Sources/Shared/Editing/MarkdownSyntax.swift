import Foundation

/// The markdown Heptad understands, and where it occurs in a note's text.
///
/// This is the app's whole formatting vocabulary, in one place. The rule it exists to keep is
/// that **every construct here has a command that can produce and remove it** — `⌘B`, `⌘I`,
/// `⌘⇧X`, `⌘⇧U` and Return. Storage that can express more than the commands can reach is what
/// let a paste leave colour and alignment behind with no way to clear them (#117).
///
/// Deliberately not a general markdown parser:
///
/// * Constructs never span lines, so a stray `*` can spoil at most its own line.
/// * Constructs never nest. `**[a](b)**` styles the outer pair and leaves the link as text.
/// * There are no backslash escapes, so text that genuinely contains `**` renders as markers.
///   A note is a scratchpad; the cost of that is cosmetic, and the parser stays small enough
///   to hold in your head.
enum MarkdownSyntax {
    /// What a run of text is, once parsed. `marker` is the syntax itself — the `**`, the
    /// `- [x] `, the `](https://…)` — which is drawn dimmed rather than hidden, because the
    /// buffer holds the source and the caret has to be able to move through it.
    enum Style: Equatable {
        case strong
        case emphasis
        case strikethrough
        case link
        case marker
    }

    struct Span: Equatable {
        let range: NSRange
        let style: Style
    }

    static let strong = "**"
    static let emphasis = "*"
    static let strikethrough = "~~"

    /// Every styled run in `text`, in source order, non-overlapping.
    static func spans(in text: NSString) -> [Span] {
        var spans: [Span] = []
        var lineStart = 0

        while lineStart < text.length {
            let lineRange = text.lineRange(for: NSRange(location: lineStart, length: 0))

            // `lineRange(for:)` on an in-bounds location always covers at least one character,
            // so this advances; asserting it rather than trusting it keeps a future change to
            // that call from turning into a hang.
            guard lineRange.length > 0 else { break }

            appendSpans(in: text, line: lineRange, into: &spans)
            lineStart = NSMaxRange(lineRange)
        }

        return spans
    }

    // MARK: - Lines

    private static func appendSpans(in text: NSString, line: NSRange, into spans: inout [Span]) {
        // The line range includes its terminator, which is never part of a construct.
        var content = line
        while content.length > 0, isNewline(text.character(at: NSMaxRange(content) - 1)) {
            content.length -= 1
        }
        guard content.length > 0 else { return }

        var cursor = content.location

        // The list grammar lives in `ListContinuation` — the file that continues these markers
        // on Return — rather than being restated here, so the two can never disagree about what
        // a marker is.
        if let length = ListContinuation.markerLength(on: text.substring(with: content)) {
            spans.append(Span(range: NSRange(location: cursor, length: length), style: .marker))
            cursor += length
        }

        let inline = NSRange(location: cursor, length: NSMaxRange(content) - cursor)
        appendInlineSpans(in: text, range: inline, into: &spans)
    }

    // MARK: - Inline

    /// Longest delimiter first: `**` has to be tried before `*`, or every bold run would parse
    /// as two empty emphasis runs.
    private static func appendInlineSpans(
        in text: NSString, range: NSRange, into spans: inout [Span]
    ) {
        let limit = NSMaxRange(range)
        var cursor = range.location

        while cursor < limit {
            let matched =
                link(in: text, at: cursor, limit: limit, into: &spans)
                ?? delimited(strong, .strong, in: text, at: cursor, limit: limit, into: &spans)
                ?? delimited(
                    strikethrough, .strikethrough, in: text, at: cursor, limit: limit, into: &spans)
                ?? delimited(emphasis, .emphasis, in: text, at: cursor, limit: limit, into: &spans)

            cursor = matched ?? cursor + 1
        }
    }

    /// Matches `<delimiter>content<delimiter>` at `start`, appending its spans and returning the
    /// index just past it. nil means no match, and nothing was appended.
    ///
    /// The whitespace rules are what keep arithmetic and shell globs out of the parser: in
    /// `2 * 3 * 4` the opening `*` is followed by a space, so it opens nothing.
    private static func delimited(
        _ delimiter: String, _ style: Style, in text: NSString, at start: Int, limit: Int,
        into spans: inout [Span]
    ) -> Int? {
        let width = delimiter.utf16.count
        guard matches(delimiter, in: text, at: start, limit: limit) else { return nil }

        let contentStart = start + width
        guard contentStart < limit, !isWhitespace(text.character(at: contentStart)) else {
            return nil
        }

        // A `*` that opens a `**` run belongs to the longer delimiter, which was already tried
        // and declined — so this one has to decline too rather than claim half of it.
        if width == 1, matches(delimiter, in: text, at: contentStart, limit: limit) { return nil }

        var closing = contentStart + 1
        while closing + width <= limit {
            if matches(delimiter, in: text, at: closing, limit: limit),
                !isWhitespace(text.character(at: closing - 1))
            {
                spans.append(Span(range: NSRange(location: start, length: width), style: .marker))
                spans.append(
                    Span(
                        range: NSRange(location: contentStart, length: closing - contentStart),
                        style: style))
                spans.append(Span(range: NSRange(location: closing, length: width), style: .marker))
                return closing + width
            }
            closing += 1
        }

        return nil
    }

    /// Matches `[label](url)` at `start`. Both halves must be non-empty: `[]()` is text.
    private static func link(
        in text: NSString, at start: Int, limit: Int, into spans: inout [Span]
    ) -> Int? {
        guard matches("[", in: text, at: start, limit: limit),
            let labelEnd = index(of: "]", in: text, from: start + 1, limit: limit),
            labelEnd > start + 1,
            matches("(", in: text, at: labelEnd + 1, limit: limit),
            let urlEnd = index(of: ")", in: text, from: labelEnd + 2, limit: limit),
            urlEnd > labelEnd + 2
        else { return nil }

        spans.append(Span(range: NSRange(location: start, length: 1), style: .marker))
        spans.append(
            Span(range: NSRange(location: start + 1, length: labelEnd - start - 1), style: .link))
        spans.append(
            Span(range: NSRange(location: labelEnd, length: urlEnd - labelEnd + 1), style: .marker))

        return urlEnd + 1
    }

    // MARK: - Scanning

    private static func matches(_ needle: String, in text: NSString, at index: Int, limit: Int)
        -> Bool
    {
        let units = Array(needle.utf16)
        guard index >= 0, index + units.count <= limit else { return false }
        return units.enumerated().allSatisfy { text.character(at: index + $0.offset) == $0.element }
    }

    private static func index(of needle: String, in text: NSString, from: Int, limit: Int) -> Int? {
        var cursor = from
        while cursor < limit {
            if matches(needle, in: text, at: cursor, limit: limit) { return cursor }
            cursor += 1
        }
        return nil
    }

    private static func isWhitespace(_ character: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(character) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }

    private static func isNewline(_ character: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(character) else { return false }
        return CharacterSet.newlines.contains(scalar)
    }
}
