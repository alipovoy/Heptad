import Foundation

/// The scanner: where each construct in `MarkdownSyntax`'s vocabulary occurs in a note's text.
///
/// Split from the vocabulary because the two are read for different reasons: that file is what the
/// app can express, this one is how it is recognised. Nothing outside needs any of it but
/// `spans(in:)`.
extension MarkdownSyntax {
    /// Every styled run in `text`, in source order.
    ///
    /// Parsed line by line, because a construct never spans lines — which is also what would make
    /// a range-scoped overload safe, if anything wanted one. Nothing does: rendering repaints the
    /// whole note.
    ///
    /// Spans may overlap, because constructs nest — an emphasis run inside a strong one is two
    /// spans over the same characters, the outer appended first.
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
            spans.append(Span(range: NSRange(location: cursor, length: length), style: .listMarker))
            cursor += length
        }

        let inline = NSRange(location: cursor, length: NSMaxRange(content) - cursor)
        appendInlineSpans(in: text, range: inline, into: &spans)
    }

    // MARK: - Inline

    /// The order below is load-bearing wherever one delimiter is a prefix of another: `***` is
    /// matched before `**`, and `**` before `*`, so the longest spelling claims the run instead of
    /// leaving its remainder as a stray character. The rest are disjoint and their order is only a
    /// convention.
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

        /// Every style the pair carries — more than one only for `***`, which is bold and italic
        /// in a single pair rather than the `**` and `_` this app writes them as.
        let styles: [Style]

        var width: Int { characters.utf16.count }
    }

    private static let inlineDelimiters = [
        Delimiter(characters: strongEmphasis, styles: [.strong, .emphasis]),
        Delimiter(characters: strong, styles: [.strong]),
        Delimiter(characters: strikethrough, styles: [.strikethrough]),
        Delimiter(characters: emphasis, styles: [.emphasis]),
        Delimiter(characters: emphasisAlternate, styles: [.emphasis])
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
            canOpen(characters, in: text, at: start, bounds: bounds)
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
            if closes(delimiter, in: text, at: closing, bounds: bounds) {
                let content = NSRange(location: contentStart, length: closing - contentStart)

                spans.append(Span(range: NSRange(location: start, length: width), style: .marker))

                // One span per style, over the same characters. `MarkdownStyling.restyle` reads
                // each run's current font, so the two compose into a bold italic face.
                for style in delimiter.styles {
                    spans.append(Span(range: content, style: style))
                }

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
    /// whitespace, and it falls where the boundary rules for its own spelling allow.
    private static func closes(
        _ delimiter: Delimiter, in text: NSString, at index: Int, bounds: NSRange
    ) -> Bool {
        matches(delimiter.characters, in: text, at: index, limit: NSMaxRange(bounds))
            && !isEscaped(index, in: text)
            && !isWhitespace(text.character(at: index - 1))
            && canClose(delimiter.characters, in: text, at: index, bounds: bounds)
    }

    // MARK: - Boundaries
    //
    // `_` has to sit at a word boundary. Without that rule the app would italicise the middle of
    // `AWS_SECRET_KEY` and `snake_case_name` — precisely the sort of thing these notes hold, and
    // the rule is what makes `_` safe to spell italic with.
    //
    // `*` is italic's fallback spelling, written wherever `_` would not read back, so the same rule
    // would take that spelling away — `Test*ing*` has to be italic. It got no rule at all instead,
    // and a note holding `/usr/*/bin/*x` drew as `/usr//bin/x` with `/bin/` italic and the
    // asterisks hidden. CommonMark's flanking rules are the ones that tell those two apart, and
    // being the ones every other parser uses, they are also what the note means elsewhere.
    //
    // `***`, `**` and `~~` still have no rule of their own: bold has no fallback spelling to keep
    // working, so flanking there would cost the trait rather than protect the text — `a**/usr**`
    // could not open, and the line would fall to `Spelling.plain`. See `Spelling.Italic`.

    private static func canOpen(
        _ delimiter: String, in text: NSString, at index: Int, bounds: NSRange
    ) -> Bool {
        let sides = neighbours(of: delimiter, at: index, in: text, bounds: bounds)

        switch delimiter {
        case emphasis: return sides.before.map { !isWordCharacter($0) } ?? true
        case emphasisAlternate: return flanks(inside: sides.after, outside: sides.before)
        default: return true
        }
    }

    private static func canClose(
        _ delimiter: String, in text: NSString, at index: Int, bounds: NSRange
    ) -> Bool {
        let sides = neighbours(of: delimiter, at: index, in: text, bounds: bounds)

        switch delimiter {
        case emphasis: return sides.after.map { !isWordCharacter($0) } ?? true
        case emphasisAlternate: return flanks(inside: sides.before, outside: sides.after)
        default: return true
        }
    }

    /// CommonMark's flanking test, both directions in one: the run may open or close unless the
    /// character it faces `inside` the pair is punctuation and the one `outside` is a word
    /// character. nil is the line's own end, which counts as whitespace and frees the delimiter.
    ///
    /// So the closing `*` of `/usr/*/bin/*x` faces `/` inside and `x` outside and cannot close,
    /// while in `Test*ing*` it faces `g`, which is no punctuation, and closes.
    private static func flanks(inside: unichar?, outside: unichar?) -> Bool {
        guard let inside, isPunctuation(inside) else { return true }
        guard let outside else { return true }

        return isWhitespace(outside) || isPunctuation(outside)
    }

    /// The characters either side of a delimiter run, nil where the line ends.
    private static func neighbours(
        of delimiter: String, at index: Int, in text: NSString, bounds: NSRange
    ) -> (before: unichar?, after: unichar?) {
        let end = index + delimiter.utf16.count

        return (
            before: index > bounds.location ? text.character(at: index - 1) : nil,
            after: end < NSMaxRange(bounds) ? text.character(at: end) : nil)
    }

    // MARK: - Links

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

        let label = NSRange(location: start + 1, length: labelEnd - start - 1)

        spans.append(Span(range: NSRange(location: start, length: 1), style: .marker))
        spans.append(Span(range: label, style: .link))
        appendEscapeMarkers(in: text, over: label, into: &spans)
        spans.append(
            Span(range: NSRange(location: labelEnd, length: urlEnd - labelEnd + 1), style: .marker))

        return urlEnd + 1
    }

    /// Hides each `\` that escapes something inside a link's label.
    ///
    /// A label is deliberately not parsed — `[**a**](b)` reads literally — but `index(of:)` honours
    /// escapes when it looks for the closing `]`, which is the only reason a label can hold one.
    /// Without this, the `\` of `[a\]b](url)` stayed visible in the label.
    private static func appendEscapeMarkers(
        in text: NSString, over label: NSRange, into spans: inout [Span]
    ) {
        var cursor = label.location
        let limit = NSMaxRange(label)

        while cursor < limit {
            guard let past = escaped(in: text, at: cursor, limit: limit) else {
                cursor += 1
                continue
            }

            spans.append(Span(range: NSRange(location: cursor, length: 1), style: .marker))
            cursor = past
        }
    }

    /// The `)` that ends a link's destination: the first one not closing a `(` opened inside it.
    ///
    /// Parentheses are balanced, as CommonMark balances them, because pasted addresses have them:
    /// `https://en.wikipedia.org/wiki/Foo_(bar)` is one URL. Unbalanced still means no link — an
    /// address holding a lone `)` is one this app has no spelling for.
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
}
