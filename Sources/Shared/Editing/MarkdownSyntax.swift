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
/// * A backslash escapes the character after it when that character is one this file can act on:
///   `\*\*text\*\*` is four literal asterisks, not a bold run. It is what lets a note hold the
///   markdown it is talking *about* — `MarkdownWriting` puts the backslashes in when the text
///   would otherwise be read back as formatting the user never applied.
enum MarkdownSyntax {
    /// What a run of text is, once parsed.
    ///
    /// The two kinds of syntax are deliberately separate, because formatted mode does opposite
    /// things with them:
    ///
    /// * `marker` is the delimiter the user never meant to look at — the `**`, the `_`, the
    ///   `](https://…)`. It describes the run beside it and does not survive into rich text.
    /// * `listMarker` is the `- `, `1. ` or `- [x] ` at the head of a line. It is content: the
    ///   user typed it, or pressed Return and had it typed for them, and a list whose bullets
    ///   went missing is not a list. It survives as the characters it is.
    ///
    /// An escaping backslash is a `marker` too: it says what the character after it is *not*, and
    /// having said it, it has no business on screen.
    enum Style: Equatable {
        case strong
        case emphasis
        case strikethrough
        case link
        case marker
        case listMarker
    }

    struct Span: Equatable {
        let range: NSRange
        let style: Style
    }

    static let strong = "**"

    /// Italic is written `_` by preference, and this is the delimiter the word-boundary rule
    /// below is about: `_` never opens or closes against a word character, so `AWS_SECRET_KEY`
    /// and `snake_case_name` are names rather than italics.
    static let emphasis = "_"

    /// The other spelling of italic, for the runs `_` refuses — `Test_ing_` is italic to no
    /// markdown parser, and `⌘I` has to be writable wherever the caret is. `*` minds no
    /// boundaries, so it covers exactly those.
    ///
    /// Read here, but written only as `MarkdownWriting`'s fallback, because text is full of loose
    /// asterisks. What keeps them ordinary is this file's own rules: a delimiter never opens
    /// against whitespace, so `2 * 3` and `SELECT * FROM` mean what they say, and `**` is matched
    /// before `*` is tried, so a bold pair is never read as two italic ones.
    static let emphasisAlternate = "*"

    static let strikethrough = "~~"

    /// The one character that changes what the next one means.
    static let escape: Character = "\\"

    /// What a backslash can be put in front of: every character this file acts on, and itself.
    /// A backslash before anything else is an ordinary backslash — these notes hold paths and
    /// regexes, and doubling every one of those would be its own kind of noise.
    static func isEscapable(_ character: Character) -> Bool {
        "*_~[]()\\".contains(character)
    }

    static func isEscapable(_ character: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(character) else { return false }
        return isEscapable(Character(scalar))
    }

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
            spans.append(Span(range: NSRange(location: cursor, length: length), style: .listMarker))
            cursor += length
        }

        let inline = NSRange(location: cursor, length: NSMaxRange(content) - cursor)
        appendInlineSpans(in: text, range: inline, into: &spans)
    }

    // MARK: - Inline

    /// The order below is load-bearing for one pair: `*` is a prefix of `**`, so `**` is matched
    /// first and a bold pair is never read as two italic ones. The rest are disjoint and their
    /// order is only a convention.
    ///
    /// `range` is also the boundary a `_` measures itself against, so a construct's content can
    /// be handed straight back here to be parsed in its own right.
    private static func appendInlineSpans(
        in text: NSString, range: NSRange, into spans: inout [Span]
    ) {
        let limit = NSMaxRange(range)
        var cursor = range.location

        while cursor < limit {
            // An escape is taken first and takes the character after it with it, so an escaped
            // delimiter never gets the chance to open anything.
            if let past = escaped(in: text, at: cursor, limit: limit) {
                spans.append(Span(range: NSRange(location: cursor, length: 1), style: .marker))
                cursor = past
                continue
            }

            var matched = link(in: text, at: cursor, limit: limit, into: &spans)

            for delimiter in inlineDelimiters where matched == nil {
                matched = delimited(delimiter, in: text, at: cursor, bounds: range, into: &spans)
            }

            cursor = matched ?? cursor + 1
        }
    }

    /// A delimiter and what it means, so the scan passes one thing where it used to pass two.
    private struct Delimiter {
        let characters: String
        let style: Style

        var width: Int { characters.utf16.count }
    }

    private static let inlineDelimiters = [
        Delimiter(characters: strong, style: .strong),
        Delimiter(characters: strikethrough, style: .strikethrough),
        Delimiter(characters: emphasis, style: .emphasis),
        Delimiter(characters: emphasisAlternate, style: .emphasis)
    ]

    /// Matches `<delimiter>content<delimiter>` at `start`, appending its spans and returning the
    /// index just past it. nil means no match, and nothing was appended.
    ///
    /// The whitespace rules are what keep arithmetic and shell globs out of the parser: in
    /// `2 * 3 * 4` the opening `*` is followed by a space, so it opens nothing.
    private static func delimited(
        _ delimiter: Delimiter, in text: NSString, at start: Int, bounds: NSRange,
        into spans: inout [Span]
    ) -> Int? {
        let characters = delimiter.characters
        let width = delimiter.width
        let limit = NSMaxRange(bounds)

        guard matches(characters, in: text, at: start, limit: limit),
            canOpen(characters, in: text, at: start, lowerBound: bounds.location)
        else { return nil }

        let contentStart = start + width
        guard contentStart < limit, !isWhitespace(text.character(at: contentStart)) else {
            return nil
        }

        // A doubled one-character delimiter opens nothing: `__` is not this app's spelling of
        // anything, and reading it as an empty run would leave the rest of the line mis-styled.
        if width == 1, matches(characters, in: text, at: contentStart, limit: limit) { return nil }

        var closing = contentStart + 1
        while closing + width <= limit {
            if closes(delimiter, in: text, at: closing, limit: limit) {
                let content = NSRange(location: contentStart, length: closing - contentStart)

                spans.append(Span(range: NSRange(location: start, length: width), style: .marker))
                spans.append(Span(range: content, style: delimiter.style))

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

    /// Whether a delimiter at `index` closes a run: it is there, it does not close against
    /// whitespace, and it falls at a word boundary if it is one that must.
    private static func closes(
        _ delimiter: Delimiter, in text: NSString, at index: Int, limit: Int
    ) -> Bool {
        matches(delimiter.characters, in: text, at: index, limit: limit)
            && !isEscaped(index, in: text)
            && !isWhitespace(text.character(at: index - 1))
            && canClose(delimiter.characters, in: text, at: index, limit: limit)
    }

    // MARK: - Word boundaries
    //
    // `_` is the one delimiter that has to sit at a word boundary. Without this rule the app
    // would italicise the middle of `AWS_SECRET_KEY` and `snake_case_name` — which is precisely
    // the sort of thing these notes hold, so the rule is what makes `_` safe to spell italic
    // with. `**`, `~~` and `*` need no such rule: nobody writes them inside an identifier.

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

    /// Not private: `MarkdownWriting` asks the same question when it chooses between `_` and `*`,
    /// so the pair it writes is one this file reads back.
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
            let urlEnd = destinationEnd(in: text, from: labelEnd + 2, limit: limit),
            urlEnd > labelEnd + 2
        else { return nil }

        spans.append(Span(range: NSRange(location: start, length: 1), style: .marker))
        spans.append(
            Span(range: NSRange(location: start + 1, length: labelEnd - start - 1), style: .link))
        spans.append(
            Span(range: NSRange(location: labelEnd, length: urlEnd - labelEnd + 1), style: .marker))

        return urlEnd + 1
    }

    /// The `)` that ends a link's destination: the first one not closing a `(` opened inside it.
    ///
    /// Parentheses in a destination are balanced, as CommonMark balances them, because the
    /// addresses people paste into notes have them —
    /// `https://en.wikipedia.org/wiki/Foo_(bar)` is one URL. Taking the first `)` instead gave a
    /// dead link and left the tail of the address sitting in the note as text.
    ///
    /// Unbalanced still means no link: an address holding a lone `)` is one this app has no
    /// spelling for, and the writer's ladder drops the link rather than the characters.
    private static func destinationEnd(in text: NSString, from: Int, limit: Int) -> Int? {
        var depth = 0
        var cursor = from

        while cursor < limit {
            defer { cursor += 1 }
            guard !isEscaped(cursor, in: text) else { continue }

            if matches("(", in: text, at: cursor, limit: limit) {
                depth += 1
            } else if matches(")", in: text, at: cursor, limit: limit) {
                guard depth > 0 else { return cursor }
                depth -= 1
            }
        }

        return nil
    }

    // MARK: - Escapes

    /// The index just past `\x` when one starts at `index`, or nil when it does not.
    private static func escaped(in text: NSString, at index: Int, limit: Int) -> Int? {
        guard index + 1 < limit, text.character(at: index) == escapeCharacter,
            isEscapable(text.character(at: index + 1))
        else { return nil }

        return index + 2
    }

    /// Whether the character at `index` is spoken for by a backslash in front of it.
    ///
    /// Counted rather than checked one back: `\\` is an escaped backslash, so it leaves the
    /// character after it free. An odd number of them escapes, an even number does not.
    private static func isEscaped(_ index: Int, in text: NSString) -> Bool {
        var backslashes = 0
        var cursor = index - 1

        while cursor >= 0, text.character(at: cursor) == escapeCharacter {
            backslashes += 1
            cursor -= 1
        }

        return backslashes.isMultiple(of: 2) == false
    }

    private static let escapeCharacter = Array(String(escape).utf16)[0]

    // MARK: - Scanning

    private static func matches(
        _ needle: String, in text: NSString, at index: Int, limit: Int
    ) -> Bool {
        let units = Array(needle.utf16)
        guard index >= 0, index + units.count <= limit else { return false }
        return units.enumerated().allSatisfy { text.character(at: index + $0.offset) == $0.element }
    }

    /// The first unescaped `needle` at or after `from`. Escaped ones are passed over, which is
    /// what lets a label hold a `]` and a note hold a literal `[docs](url)`.
    private static func index(of needle: String, in text: NSString, from: Int, limit: Int) -> Int? {
        var cursor = from
        while cursor < limit {
            if matches(needle, in: text, at: cursor, limit: limit), !isEscaped(cursor, in: text) {
                return cursor
            }
            cursor += 1
        }
        return nil
    }

    /// Not private: the commands and the writer trim to the same idea of whitespace this parser
    /// refuses to close a delimiter against, so neither can emit markdown it would reject.
    static func isWhitespace(_ character: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(character) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }

    /// Not private, and for the same reason as `isWhitespace`: the writer has to know where a
    /// line ends to keep a construct off the terminator, and two spellings of "newline" could
    /// disagree.
    static func isNewline(_ character: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(character) else { return false }
        return CharacterSet.newlines.contains(scalar)
    }
}
