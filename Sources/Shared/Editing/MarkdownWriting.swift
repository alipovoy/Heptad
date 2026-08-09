import Foundation

/// What the user sees in, markdown source out — the other half of the mode switch from
/// `RichTextRendering`.
///
/// A note is stored as markdown whichever mode it is being edited in, so this runs on every save
/// of a formatted note and on every switch to plain mode. It is the only place delimiters are
/// written, and everything it writes has to be something `MarkdownSyntax` reads back the same
/// way — the three rules that takes are here rather than left to the caller:
///
/// * **A construct never spans lines.** A bold run dragged across a paragraph is written as one
///   pair per line, not one pair around the lot.
/// * **A delimiter never closes against whitespace,** so the whitespace at the edges of a run is
///   written outside the pair.
/// * **Text that would read as formatting is escaped.** A user who types `**bold**` in formatted
///   mode meant those asterisks, and a save that quietly turned them into a bold run would be the
///   app rewriting the note behind them.
///
/// Nesting is by a fixed order, so overlapping runs come out properly nested rather than
/// interleaved, which markdown cannot express at all.
enum MarkdownWriting {
    /// Writes each line, then checks it: if reading the line back would not give the line that
    /// went in, it is written again with every escapable character escaped.
    ///
    /// Checked rather than predicted, because what needs escaping depends on what ends up beside
    /// it. Text ending in `*` next to a bold run writes `a***b**`, which reads back as a bold
    /// `*b` — no rule about the plain text alone would have caught that, and the check does.
    ///
    /// Per line, because escapes are noise in the source and a note is read in that mode too: a
    /// line that needs them gets them, and the rest of the note stays as clean as it reads.
    static func markdown(from attributed: NSAttributedString) -> String {
        let whole = NSRange(location: 0, length: attributed.length)

        return lines(of: whole, in: attributed).reduce(into: "") { markdown, line in
            let written = emit(line, of: attributed, escaping: false)
            let readsBack = reads(written, as: attributed.attributedSubstring(from: line))

            markdown += readsBack ? written : emit(line, of: attributed, escaping: true)
        }
    }

    // MARK: - Checking

    /// Whether `markdown` reads back as the text it was written from — same characters, same
    /// emphasis on each of them, same links.
    ///
    /// The characters alone are not enough. `a***b**` has exactly the characters of `a*` followed
    /// by a bold `b`, and reads back as a bold `*b`; only comparing the formatting catches it.
    private static func reads(_ markdown: String, as original: NSAttributedString) -> Bool {
        let rendered = RichTextRendering.attributed(from: markdown, appearance: reading)
        guard rendered.string == original.string else { return false }

        for index in 0..<rendered.length {
            let read = rendered.attributes(at: index, effectiveRange: nil)
            let intended = original.attributes(at: index, effectiveRange: nil)

            guard Emphasis.allCases.allSatisfy({ $0.isOn(read) == $0.isOn(intended) }),
                destination(read[.link]) == destination(intended[.link])
            else { return false }
        }

        return true
    }

    /// The appearance the check reads with. Only the traits are compared, and those do not depend
    /// on a size, so the note's own zoom never has to reach this file.
    private static let reading = MarkdownStyling.Appearance(
        plainText: false, fontSize: AppConstants.Layout.defaultFontSize)

    // MARK: - Links

    /// Links first, because a link's label is not parsed: `[**a**](b)` is a link whose label
    /// reads literally, so whatever is inside one is written as plain characters.
    private static func emit(
        _ range: NSRange, of text: NSAttributedString, escaping: Bool
    ) -> String {
        guard range.length > 0 else { return "" }

        var markdown = ""
        text.enumerateAttribute(.link, in: range, options: []) { value, subrange, _ in
            let label = content(subrange, of: text, escaping: escaping)

            // A link that got dragged across a line break is not one the parser would read back,
            // so it is written as the text it holds.
            guard let destination = destination(value), !label.contains(where: \.isNewline) else {
                markdown += wrap(subrange, of: text, in: Emphasis.allCases, escaping: escaping)
                return
            }

            // The destination is written as it is: a URL holding a bracket of its own is a link
            // this app cannot spell either way, and escaping inside one would only move the
            // problem into the address.
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
        _ range: NSRange, of text: NSAttributedString, in traits: [Emphasis], escaping: Bool
    ) -> String {
        guard let trait = traits.first else { return content(range, of: text, escaping: escaping) }
        let rest = Array(traits.dropFirst())

        var markdown = ""
        for section in sections(of: range, in: text, carrying: trait) {
            guard section.isOn else {
                markdown += wrap(section.range, of: text, in: rest, escaping: escaping)
                continue
            }

            for line in lines(of: section.range, in: text) {
                markdown += delimited(line, of: text, with: trait, then: rest, escaping: escaping)
            }
        }

        return markdown
    }

    /// One line's worth of a run, with the pair written around its non-whitespace core.
    private static func delimited(
        _ line: NSRange, of text: NSAttributedString, with trait: Emphasis, then rest: [Emphasis],
        escaping: Bool
    ) -> String {
        let source = text.string as NSString
        let core = trimmed(line, in: source)

        // Nothing but whitespace, or a spelling the parser would not read back — `_` between two
        // word characters is an identifier, not italic. Either way the characters are written as
        // they are: losing the trait beats writing delimiters that come back as literal text.
        guard core.length > 0, readsBack(trait, around: core, in: source) else {
            return content(line, of: text, escaping: escaping)
        }

        let before = NSRange(location: line.location, length: core.location - line.location)
        let after = NSRange(
            location: NSMaxRange(core), length: NSMaxRange(line) - NSMaxRange(core))

        return content(before, of: text, escaping: escaping)
            + trait.delimiter
            + wrap(core, of: text, in: rest, escaping: escaping)
            + trait.delimiter
            + content(after, of: text, escaping: escaping)
    }

    /// Whether a pair written around `core` is one `MarkdownSyntax` would read as this trait.
    /// Only `_` can fail, and only against a word character — see `MarkdownSyntax.isWordCharacter`.
    private static func readsBack(
        _ trait: Emphasis, around core: NSRange, in source: NSString
    ) -> Bool {
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

    // MARK: - Characters

    /// The user's own characters, with a backslash in front of every one that would otherwise be
    /// read as syntax.
    ///
    /// All of them or none of them, decided per line by the check above. Escaping only the
    /// characters that happen to be part of a construct *this* time would leave the result
    /// depending on what the parser found, which is the thing being defended against.
    private static func content(
        _ range: NSRange, of text: NSAttributedString, escaping: Bool
    ) -> String {
        guard range.length > 0 else { return "" }
        let characters = (text.string as NSString).substring(with: range)
        guard escaping else { return characters }

        return characters.reduce(into: "") { escaped, character in
            if MarkdownSyntax.isEscapable(character) { escaped.append(MarkdownSyntax.escape) }
            escaped.append(character)
        }
    }
}
