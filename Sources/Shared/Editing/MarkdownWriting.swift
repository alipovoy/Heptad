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
    /// went in, it is written again with every escapable character escaped — and if that is not
    /// the line either, as the line's own characters with no formatting at all.
    ///
    /// Checked rather than predicted, because what needs escaping depends on what ends up beside
    /// it. Text ending in `*` next to a bold run writes `a***b**`, which reads back as a bold
    /// `*b` — no rule about the plain text alone would have caught that, and the check does.
    ///
    /// The last candidate is the one that ends the ladder, and it is written without being
    /// checked because it cannot be wrong about the characters: it holds no delimiters, and
    /// everything the parser would act on has a backslash in front of it. Something has to be
    /// unconditional, or a line the check rejects twice is written rejected — which is how a link
    /// this app cannot spell used to change the note's own text. **A save may lose formatting; it
    /// may never lose a character.**
    ///
    /// Per line, because escapes are noise in the source and a note is read in that mode too: a
    /// line that needs them gets them, and the rest of the note stays as clean as it reads.
    static func markdown(from attributed: NSAttributedString) -> String {
        let whole = NSRange(location: 0, length: attributed.length)

        return lines(of: whole, in: attributed).reduce(into: "") { markdown, line in
            let original = attributed.attributedSubstring(from: line)

            for spelling in Spelling.ladder {
                let written = emit(line, of: attributed, as: spelling)
                guard reads(written, as: original) else { continue }

                markdown += written
                return
            }

            markdown += content(line, of: attributed, as: .plain)
        }
    }

    /// How hard one candidate line tries, and the order they are tried in.
    ///
    /// Two independent retreats, because they give up different things. Escaping costs the source
    /// its cleanliness; caution costs the note a trait. Neither is worth spending until the
    /// spelling that keeps both has been written and rejected.
    private struct Spelling {
        /// Every character the parser could act on gets a backslash in front of it.
        let escaping: Bool

        /// A `_` pair whose neighbours in the *rendered* text are word characters is not written
        /// at all, and the trait is dropped instead.
        ///
        /// A conservative test, and knowingly so: it is blind to the delimiters the writer is
        /// about to put between those neighbours, so it refuses pairs that would have read back
        /// perfectly — `the **_hard_**ware` among them. That is why it cannot be a precondition.
        /// As a late rung it is the right question, because by then the permissive spelling has
        /// already been tried and rejected, and the choice left is between dropping this one
        /// trait and dropping every trait on the line.
        let cautious: Bool

        /// Most faithful first. `markdown(from:)` writes the first that reads back, and its own
        /// unconditional fallback is what happens when none of them does.
        static let ladder = [
            Self(escaping: false, cautious: false),
            Self(escaping: true, cautious: false),
            Self(escaping: false, cautious: true),
            Self(escaping: true, cautious: true)
        ]

        /// The characters alone, escaped. No delimiters are written under this one.
        static let plain = Self(escaping: true, cautious: true)
    }

    // MARK: - Checking

    /// Whether `markdown` reads back as the text it was written from: the same characters, and no
    /// formatting on them the text did not already have.
    ///
    /// The characters alone are not enough. `a***b**` has exactly the characters of `a*` followed
    /// by a bold `b`, and reads back as a bold `*b`; only comparing the formatting catches it.
    ///
    /// Asymmetric on purpose, and this is the half that is easy to get wrong. Formatting the
    /// writer *cannot spell* is dropped by design — the whitespace at the edge of a run goes
    /// outside the pair, a run never spans a line, and a trait covering half a link has nowhere
    /// to be written. Those are the rules at the top of this file, so a check that called them
    /// failures would reject the writer's own correct output and send the line to a candidate
    /// that keeps less. What must never pass is the other direction: emphasis appearing on
    /// characters that never carried it, which is the whole reason escaping exists.
    private static func reads(_ markdown: String, as original: NSAttributedString) -> Bool {
        let rendered = RichTextRendering.attributed(from: markdown, appearance: reading)
        guard rendered.string == original.string else { return false }

        for index in 0..<rendered.length {
            let read = rendered.attributes(at: index, effectiveRange: nil)
            let intended = original.attributes(at: index, effectiveRange: nil)
            let link = destination(read[.link])

            guard Emphasis.allCases.allSatisfy({ !$0.isOn(read) || $0.isOn(intended) }),
                link == nil || link == destination(intended[.link])
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
    ///
    /// Emphasis over a link is written *around* it — `**[docs](url)**` — which is the spelling
    /// the parser already reads. Inside the brackets there is nowhere to put it.
    private static func emit(
        _ range: NSRange, of text: NSAttributedString, as spelling: Spelling
    ) -> String {
        guard range.length > 0 else { return "" }
        let source = text.string as NSString

        var markdown = ""
        text.enumerateAttribute(.link, in: range, options: []) { value, subrange, _ in
            // The terminator is not part of the label. `markdown(from:)` has already split by
            // line, so a link carrying one is a link that reaches the end of its line, not one
            // spanning two — and writing the `\n` inside the brackets is what used to drop it
            // everywhere except the note's last line, where there is no terminator to carry.
            let core = withoutTerminator(subrange, in: source)

            guard let destination = destination(value), core.length > 0 else {
                markdown += wrap(subrange, of: text, in: Emphasis.allCases, as: spelling)
                return
            }

            let terminator = NSRange(
                location: NSMaxRange(core), length: NSMaxRange(subrange) - NSMaxRange(core))

            // The destination is written as it is: a URL holding a bracket of its own is a link
            // this app cannot spell either way, and escaping inside one would only move the
            // problem into the address.
            let traits = uniform(over: core, in: text)
            markdown += traits.map(\.delimiter).joined()
                + "[" + content(core, of: text, as: spelling) + "](" + destination + ")"
                + traits.reversed().map(\.delimiter).joined()
                + content(terminator, of: text, as: spelling)
        }

        return markdown
    }

    /// `range` without the line terminator it ends with, if it ends with one.
    private static func withoutTerminator(_ range: NSRange, in source: NSString) -> NSRange {
        var end = NSMaxRange(range)

        while end > range.location, MarkdownSyntax.isNewline(source.character(at: end - 1)) {
            end -= 1
        }

        return NSRange(location: range.location, length: end - range.location)
    }

    /// The traits carried by every character of `range`, in nesting order.
    ///
    /// A pair can only be written around the whole of a link, so a trait covering part of one
    /// cannot be spelled at all — the label is not parsed, and there is no second place to put
    /// the delimiters. Those are dropped here, and the per-line check above sees it.
    private static func uniform(over range: NSRange, in text: NSAttributedString) -> [Emphasis] {
        Emphasis.allCases.filter { trait in
            var carried = true

            text.enumerateAttributes(in: range, options: []) { attributes, _, stop in
                guard trait.isOn(attributes) else {
                    carried = false
                    stop.pointee = true
                    return
                }
            }

            return carried
        }
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
        _ range: NSRange, of text: NSAttributedString, in traits: [Emphasis],
        as spelling: Spelling
    ) -> String {
        guard let trait = traits.first else { return content(range, of: text, as: spelling) }
        let rest = Array(traits.dropFirst())

        var markdown = ""
        for section in sections(of: range, in: text, carrying: trait) {
            guard section.isOn else {
                markdown += wrap(section.range, of: text, in: rest, as: spelling)
                continue
            }

            for line in lines(of: section.range, in: text) {
                markdown += delimited(line, of: text, with: trait, then: rest, as: spelling)
            }
        }

        return markdown
    }

    /// One line's worth of a run, with the pair written around its non-whitespace core.
    private static func delimited(
        _ line: NSRange, of text: NSAttributedString, with trait: Emphasis, then rest: [Emphasis],
        as spelling: Spelling
    ) -> String {
        let source = text.string as NSString
        let core = trimmed(line, in: source)

        // Nothing to put a pair around: whitespace has to stay outside one, so a run that is all
        // whitespace is written as the characters it is. On a cautious spelling, the same is done
        // with a `_` pair the rendered text says would not read back — losing the one trait rather
        // than the whole line.
        guard core.length > 0, !spelling.cautious || mayClose(trait, around: core, in: source) else {
            return content(line, of: text, as: spelling)
        }

        let before = NSRange(location: line.location, length: core.location - line.location)
        let after = NSRange(
            location: NSMaxRange(core), length: NSMaxRange(line) - NSMaxRange(core))

        return content(before, of: text, as: spelling)
            + trait.delimiter
            + wrap(core, of: text, in: rest, as: spelling)
            + trait.delimiter
            + content(after, of: text, as: spelling)
    }

    /// Whether a pair written around `core` could be one `MarkdownSyntax` reads as this trait,
    /// judged on the neighbours it has in the rendered text. Only `_` can fail, and only against
    /// a word character — see `MarkdownSyntax.isWordCharacter`.
    ///
    /// A lower bound, not an answer: the delimiters this writer is about to put between `core`
    /// and those neighbours are not here to be seen, so a pair that would have read back can
    /// still be refused. `Spelling.cautious` is where that is the right trade and says why.
    private static func mayClose(
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
        _ range: NSRange, of text: NSAttributedString, as spelling: Spelling
    ) -> String {
        guard range.length > 0 else { return "" }
        let characters = (text.string as NSString).substring(with: range)
        guard spelling.escaping else { return characters }

        return characters.reduce(into: "") { escaped, character in
            if MarkdownSyntax.isEscapable(character) { escaped.append(MarkdownSyntax.escape) }
            escaped.append(character)
        }
    }
}
