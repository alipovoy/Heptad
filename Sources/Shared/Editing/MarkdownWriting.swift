import Foundation

/// What the user sees in, markdown source out — the other half of the mode switch from
/// `RichTextRendering`.
///
/// A note is stored as markdown whichever mode it is being edited in, so this runs on every save
/// of a formatted note and on every switch to plain mode. It is the only place delimiters are
/// written, and everything it writes has to be something `MarkdownSyntax` reads back the same
/// way — the two rules that takes are here rather than left to the caller:
///
/// * **A construct never spans lines.** A bold run dragged across a paragraph is written as one
///   pair per line, not one pair around the lot.
/// * **A delimiter never closes against whitespace,** so the whitespace at the edges of a run is
///   written outside the pair.
///
/// Nesting is by a fixed order — strong, then strikethrough, then emphasis — so overlapping runs
/// come out properly nested rather than interleaved, which markdown cannot express at all.
enum MarkdownWriting {
    static func markdown(from attributed: NSAttributedString) -> String {
        emit(NSRange(location: 0, length: attributed.length), of: attributed)
    }

    // MARK: - Links

    /// Links first, because a link's label is not parsed: `[**a**](b)` is a link whose label
    /// reads literally, so whatever is inside one is written as plain characters.
    private static func emit(_ range: NSRange, of text: NSAttributedString) -> String {
        guard range.length > 0 else { return "" }

        var markdown = ""
        text.enumerateAttribute(.link, in: range, options: []) { value, subrange, _ in
            let label = string(subrange, of: text)

            // A link that got dragged across a line break is not one the parser would read back,
            // so it is written as the text it holds.
            guard let destination = destination(value), !label.contains(where: \.isNewline) else {
                markdown += wrap(subrange, of: text, in: Emphasis.allCases)
                return
            }

            markdown += "[" + label + "](" + destination + ")"
        }

        return markdown
    }

    private static func destination(_ value: Any?) -> String? {
        switch value {
        case let url as URL: url.absoluteString
        case let string as String: string
        default: nil
        }
    }

    // MARK: - Emphasis

    /// Writes `range` with the delimiters for `traits`, outermost first.
    ///
    /// The order is `Emphasis`'s own case order: bold covering half of an italic run comes out as
    /// `**a _b_** _c_`, never as the interleaved `**a _b**c_` that reads as neither.
    private static func wrap(
        _ range: NSRange, of text: NSAttributedString, in traits: [Emphasis]
    ) -> String {
        guard let trait = traits.first else { return string(range, of: text) }
        let rest = Array(traits.dropFirst())

        var markdown = ""
        for section in sections(of: range, in: text, carrying: trait) {
            guard section.isOn else {
                markdown += wrap(section.range, of: text, in: rest)
                continue
            }

            for line in lines(of: section.range, in: text) {
                markdown += delimited(line, of: text, with: trait, then: rest)
            }
        }

        return markdown
    }

    /// One line's worth of a run, with the pair written around its non-whitespace core.
    private static func delimited(
        _ line: NSRange, of text: NSAttributedString, with trait: Emphasis, then rest: [Emphasis]
    ) -> String {
        let source = text.string as NSString
        let core = trimmed(line, in: source)

        // Nothing but whitespace, or a spelling the parser would not read back — `_` between two
        // word characters is an identifier, not italic. Either way the characters are written as
        // they are: losing the trait beats writing delimiters that come back as literal text.
        guard core.length > 0, readsBack(trait, around: core, in: source) else {
            return string(line, of: text)
        }

        return string(NSRange(location: line.location, length: core.location - line.location), of: text)
            + trait.delimiter
            + wrap(core, of: text, in: rest)
            + trait.delimiter
            + string(
                NSRange(location: NSMaxRange(core), length: NSMaxRange(line) - NSMaxRange(core)),
                of: text)
    }

    /// Whether a pair written around `core` is one `MarkdownSyntax` would read as this trait.
    /// Only `_` can fail, and only against a word character — see `MarkdownSyntax.isWordCharacter`.
    private static func readsBack(_ trait: Emphasis, around core: NSRange, in source: NSString) -> Bool {
        guard MarkdownSyntax.mindsWordBoundaries(trait.delimiter) else { return true }

        let before = core.location - 1
        if before >= 0, MarkdownSyntax.isWordCharacter(source.character(at: before)) { return false }

        let after = NSMaxRange(core)
        if after < source.length, MarkdownSyntax.isWordCharacter(source.character(at: after)) {
            return false
        }

        return true
    }

    // MARK: - Slicing

    /// `range` split into stretches that do and do not carry `trait`, in order.
    private static func sections(
        of range: NSRange, in text: NSAttributedString, carrying trait: Emphasis
    ) -> [(range: NSRange, isOn: Bool)] {
        var sections: [(range: NSRange, isOn: Bool)] = []

        text.enumerateAttributes(in: range, options: []) { attributes, subrange, _ in
            let isOn = trait.isOn(attributes)

            // Runs differing in something this trait does not care about are one stretch.
            if var last = sections.last, last.isOn == isOn {
                last.range = NSUnionRange(last.range, subrange)
                sections[sections.count - 1] = last
            } else {
                sections.append((subrange, isOn))
            }
        }

        return sections
    }

    /// `range` split at its line breaks, each newline kept with the line it ends.
    private static func lines(of range: NSRange, in text: NSAttributedString) -> [NSRange] {
        let source = text.string as NSString
        var lines: [NSRange] = []
        var cursor = range.location

        while cursor < NSMaxRange(range) {
            let line = source.lineRange(for: NSRange(location: cursor, length: 0))
            let clipped = NSIntersectionRange(line, range)
            guard clipped.length > 0 else { break }

            lines.append(clipped)
            cursor = NSMaxRange(line)
        }

        return lines
    }

    private static func trimmed(_ range: NSRange, in source: NSString) -> NSRange {
        var start = range.location
        var end = NSMaxRange(range)

        while start < end, MarkdownSyntax.isWhitespace(source.character(at: start)) { start += 1 }
        while end > start, MarkdownSyntax.isWhitespace(source.character(at: end - 1)) { end -= 1 }

        return NSRange(location: start, length: end - start)
    }

    private static func string(_ range: NSRange, of text: NSAttributedString) -> String {
        guard range.length > 0 else { return "" }
        return (text.string as NSString).substring(with: range)
    }
}
