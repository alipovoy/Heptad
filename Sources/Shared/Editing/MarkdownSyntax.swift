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
/// * Constructs never span lines, so a stray `**` can spoil at most its own line.
/// * A link's label is not parsed. `[**a**](b)` is a link whose label reads literally.
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

    /// Italic is `_`, not `*`. The two spellings are interchangeable in markdown at large, but
    /// `*` is a prefix of `**`, and a delimiter that is a prefix of another delimiter cannot be
    /// toggled cleanly: `⌘I` inside `**bold**` either peels the bold pair apart or grows it
    /// without ever shrinking it again. Disjoint delimiters remove the ambiguity rather than
    /// manage it, and they leave `*` free to be an ordinary character — `2 * 3` and `SELECT *`
    /// mean what they say.
    static let emphasis = "_"

    static let strikethrough = "~~"

    /// Every styled run in `text`, in source order.
    static func spans(in text: NSString) -> [Span] {
        spans(in: text, over: NSRange(location: 0, length: text.length))
    }

    /// Every styled run on the lines `range` touches.
    ///
    /// Line-scoped parsing is what makes this range safe to ask for: a construct never spans
    /// lines, so a line's styling depends on that line and nothing else, and repainting after an
    /// edit never has to look further than the lines the edit landed on.
    ///
    /// Spans may overlap, because constructs nest — an emphasis run inside a strong one is two
    /// spans over the same characters, the outer appended first.
    static func spans(in text: NSString, over range: NSRange) -> [Span] {
        var spans: [Span] = []
        var lineStart = range.location

        // An empty range still means the line it sits on, so a deletion repaints something.
        let limit = min(max(NSMaxRange(range), range.location + 1), text.length)

        while lineStart < limit {
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

    /// Every delimiter here is disjoint from every other, so the order below is only a
    /// convention — no delimiter can be mistaken for the opening of a longer one.
    ///
    /// `range` is also the boundary a `_` measures itself against, so a construct's content can
    /// be handed straight back here to be parsed in its own right.
    private static func appendInlineSpans(
        in text: NSString, range: NSRange, into spans: inout [Span]
    ) {
        let limit = NSMaxRange(range)
        var cursor = range.location

        while cursor < limit {
            let matched =
                link(in: text, at: cursor, limit: limit, into: &spans)
                ?? delimited(
                    strong, .strong, in: text, at: cursor, lowerBound: range.location,
                    limit: limit, into: &spans)
                ?? delimited(
                    strikethrough, .strikethrough, in: text, at: cursor, lowerBound: range.location,
                    limit: limit, into: &spans)
                ?? delimited(
                    emphasis, .emphasis, in: text, at: cursor, lowerBound: range.location,
                    limit: limit, into: &spans)

            cursor = matched ?? cursor + 1
        }
    }

    /// Matches `<delimiter>content<delimiter>` at `start`, appending its spans and returning the
    /// index just past it. nil means no match, and nothing was appended.
    ///
    /// The whitespace rules are what keep arithmetic and shell globs out of the parser: in
    /// `2 * 3 * 4` the opening `*` is followed by a space, so it opens nothing.
    private static func delimited(
        _ delimiter: String, _ style: Style, in text: NSString, at start: Int, lowerBound: Int,
        limit: Int, into spans: inout [Span]
    ) -> Int? {
        let width = delimiter.utf16.count
        guard matches(delimiter, in: text, at: start, limit: limit),
            canOpen(delimiter, in: text, at: start, lowerBound: lowerBound)
        else { return nil }

        let contentStart = start + width
        guard contentStart < limit, !isWhitespace(text.character(at: contentStart)) else {
            return nil
        }

        // A doubled one-character delimiter opens nothing: `__` is not this app's spelling of
        // anything, and reading it as an empty run would leave the rest of the line mis-styled.
        if width == 1, matches(delimiter, in: text, at: contentStart, limit: limit) { return nil }

        var closing = contentStart + 1
        while closing + width <= limit {
            if matches(delimiter, in: text, at: closing, limit: limit),
                !isWhitespace(text.character(at: closing - 1)),
                canClose(delimiter, in: text, at: closing, limit: limit)
            {
                let content = NSRange(location: contentStart, length: closing - contentStart)

                spans.append(Span(range: NSRange(location: start, length: width), style: .marker))
                spans.append(Span(range: content, style: style))

                // One construct may sit inside another — `**_keys_**` is bold *and* italic — so
                // the content is parsed in its own right. Later spans are painted over earlier
                // ones, and `MarkdownStyling` merges font traits rather than replacing them, so
                // the inner run keeps the outer run's weight. Terminates because the content is
                // strictly shorter than what matched.
                appendInlineSpans(in: text, range: content, into: &spans)

                spans.append(Span(range: NSRange(location: closing, length: width), style: .marker))
                return closing + width
            }
            closing += 1
        }

        return nil
    }

    // MARK: - Word boundaries
    //
    // `_` is the one delimiter that has to sit at a word boundary. Without this rule the app
    // would italicise the middle of `AWS_SECRET_KEY` and `snake_case_name` — which is precisely
    // the sort of thing these notes hold, so the rule is what makes `_` safe to spell italic
    // with. `**` and `~~` need no such rule: nobody writes them inside an identifier.

    private static func canOpen(
        _ delimiter: String, in text: NSString, at index: Int, lowerBound: Int
    ) -> Bool {
        guard delimiter == emphasis, index > lowerBound else { return true }
        return !isWordCharacter(text.character(at: index - 1))
    }

    private static func canClose(
        _ delimiter: String, in text: NSString, at index: Int, limit: Int
    ) -> Bool {
        let after = index + delimiter.utf16.count
        guard delimiter == emphasis, after < limit else { return true }
        return !isWordCharacter(text.character(at: after))
    }

    /// Not private: `MarkdownFormatting` has to apply the same rule, or its commands would
    /// claim underscores the parser never read as delimiters.
    ///
    /// `_` counts as a word character here, which is not what CommonMark says but is what an
    /// identifier says: without it the second underscore of `__init__` opens a run the first one
    /// was refused, and the note italicises the middle of a dunder name.
    static func isWordCharacter(_ character: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(character) else { return false }
        return scalar == "_" || CharacterSet.alphanumerics.contains(scalar)
    }

    /// Whether `delimiter` is one that has to fall at a word boundary. Only `_` is.
    static func mindsWordBoundaries(_ delimiter: String) -> Bool { delimiter == emphasis }

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

    /// Not private: `MarkdownFormatting` trims selections to the same idea of whitespace this
    /// parser refuses to close a delimiter against, so the commands cannot emit markdown their
    /// own parser would reject.
    static func isWhitespace(_ character: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(character) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }

    private static func isNewline(_ character: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(character) else { return false }
        return CharacterSet.newlines.contains(scalar)
    }
}
