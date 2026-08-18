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
    /// The last candidate ends the ladder unchecked, because it cannot be wrong about the
    /// characters: no delimiters, and a backslash in front of everything the parser would act on.
    /// Something has to be unconditional — a save may lose formatting; it may never lose a
    /// character. The one exception is what a note may not hold at all, which `NoteCharacters`
    /// takes out before any of this runs.
    ///
    /// Per line, because escapes are noise in the source and a note is read in that mode too: a
    /// line that needs them gets them, and the rest of the note stays as clean as it reads.
    static func markdown(from attributed: NSAttributedString) -> String {
        let attributed = storable(attributed)
        let whole = NSRange(location: 0, length: attributed.length)
        let source = attributed.string as NSString

        return MarkdownSlicing.lines(of: whole, in: attributed).reduce(into: "") { markdown, line in
            let original = attributed.attributedSubstring(from: line)

            // Once per line, then carried down: finding it copies the line out, and every slice
            // of the line asks. See `MarkdownSlicing.markerEnd`.
            let markerEnd = MarkdownSlicing.markerEnd(ofLineAt: line.location, in: source)

            for spelling in Spelling.ladder {
                let pass = Pass(spelling: spelling, markerEnd: markerEnd)
                let written = emit(line, of: attributed, as: pass)
                guard reads(written, as: original) else { continue }

                markdown += written
                return
            }

            markdown += content(
                line, of: attributed, as: Pass(spelling: .plain, markerEnd: markerEnd))
        }
    }

    /// `attributed` without the characters a note may not hold, and the same object when there
    /// are none.
    ///
    /// Taken out here rather than as each slice is written, so every index the check compares still
    /// lines up: a placeholder that went missing between the writing and the reading looks like a
    /// line the writer got wrong.
    private static func storable(_ attributed: NSAttributedString) -> NSAttributedString {
        let source = attributed.string as NSString
        let unstorable: (Int) -> Bool = { !NoteCharacters.isStorable(source.character(at: $0)) }
        guard (0..<source.length).contains(where: unstorable) else { return attributed }

        // Built by appending the runs that stay rather than deleting the ones that go: each
        // `deleteCharacters` shifts every character after it, and coalescing the deletions into
        // ranges would not help — a `\r` in `\r\n` has a storable character on both sides.
        let filtered = NSMutableAttributedString()
        var kept = 0

        for index in 0..<source.length where unstorable(index) {
            filtered.append(attributed.attributedSubstring(from: NSRange(kept..<index)))
            kept = index + 1
        }
        filtered.append(attributed.attributedSubstring(from: NSRange(kept..<source.length)))

        return filtered
    }

    /// How hard one candidate line tries, and the order they are tried in.
    ///
    /// Two independent retreats, because they give up different things: escaping costs the source
    /// its cleanliness, caution costs the note a trait. Neither is spent until the spelling that
    /// keeps both has been written and rejected.
    private struct Spelling {
        /// Every character the parser could act on gets a backslash in front of it.
        let escaping: Bool

        /// What to do about an italic run whose neighbours in the *rendered* text would refuse a
        /// `_` pair. Every other trait is spelled one way and has no choice to make.
        let italic: Italic

        enum Italic {
            /// Write `_` regardless. First, because the test that refuses it is a lower bound —
            /// blind to the delimiters about to be written between the run and those neighbours,
            /// so it refuses pairs that read back perfectly, `the **_hard_**ware` among them.
            case preferred

            /// Write `*`, which minds no boundaries and so can be written anywhere `_` cannot.
            case fallback

            /// Write no pair, and lose the trait. What is left when `*` will not read back either —
            /// the pair landing inside a `**` one, since `**Test*ing***` is a run of asterisks no
            /// parser resolves. The choice by then is between this trait and every trait on the
            /// line.
            case dropped
        }

        /// Most faithful first. `markdown(from:)` writes the first that reads back, and its own
        /// unconditional fallback is what happens when none of them does.
        static let ladder = [Italic.preferred, .fallback, .dropped].flatMap {
            [Self(escaping: false, italic: $0), Self(escaping: true, italic: $0)]
        }

        /// The characters alone, escaped. No delimiters are written under this one.
        static let plain = Self(escaping: true, italic: .dropped)
    }

    /// One line's worth of context: the candidate spelling being tried, and where that line's
    /// list marker ends.
    ///
    /// Both are fixed for the whole of a line and every slice of it needs both, so they travel as
    /// one rather than as two more parameters on four mutually recursive functions.
    private struct Pass {
        let spelling: Spelling
        let markerEnd: Int
    }

    // MARK: - Links

    /// Links first, because a label is not parsed: `[**a**](b)` reads literally, so whatever is
    /// inside one is written as plain characters. Emphasis over a link is written *around* it —
    /// `**[docs](url)**`, the spelling the parser already reads.
    private static func emit(
        _ range: NSRange, of text: NSAttributedString, as pass: Pass
    ) -> String {
        guard range.length > 0 else { return "" }
        let source = text.string as NSString

        var markdown = ""
        text.enumerateAttribute(.link, in: range, options: []) { value, subrange, _ in
            // The terminator is not part of the label: a link carrying one reaches the end of its
            // line rather than spanning two, and a `\n` inside the brackets is not a link the
            // parser reads back.
            let core = MarkdownSlicing.withoutTerminator(subrange, in: source)

            guard let destination = destination(value), core.length > 0 else {
                markdown += wrap(subrange, of: text, in: Emphasis.allCases[...], as: pass)
                return
            }

            let terminator = NSRange(
                location: NSMaxRange(core), length: NSMaxRange(subrange) - NSMaxRange(core))

            // The destination is written as it is: a URL holding a bracket of its own cannot be
            // spelled either way, and escaping there would move the problem into the address.
            //
            // The pair goes through `delimiter` for the same reason `delimited` does: writing `_`
            // unconditionally makes every rung of the ladder produce the same bytes for an italic
            // link against a word character, and the line falls to `.plain`, which writes no
            // brackets and loses the destination. The neighbours are `core`'s either way, since the
            // pair lands outside the whole bracketed form.
            var traits: [String] = []

            for trait in uniform(over: core, in: text) {
                // Shielded by the pair this same loop has already written, which is the boundary
                // the inner one needs: what sits beside `_` in `**_[a](u)_**` is an asterisk, not
                // the word character `mayClose` found in the rendered text. Told otherwise,
                // `.fallback` writes `***[a](u)***`, which no parser resolves.
                guard
                    let delimiter = delimiter(
                        for: trait, around: core, in: source, as: pass.spelling,
                        shielded: !traits.isEmpty)
                else { continue }

                traits.append(delimiter)
            }

            // A label is not a list line, whatever the rendered text shows: the stored line starts
            // with `[`. Left the exemption, the `]` of a checkbox goes unescaped, the parser takes
            // the label to end there, and the line falls to `Spelling.plain` — no brackets written,
            // and the destination gone.
            let label = Pass(spelling: pass.spelling, markerEnd: min(pass.markerEnd, core.location))

            markdown += traits.joined()
                + "[" + content(core, of: text, as: label) + "](" + destination + ")"
                + traits.reversed().joined()
                + content(terminator, of: text, as: pass)
        }

        return markdown
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

    /// Internal rather than `private`: `MarkdownReadback` compares destinations too, and
    /// `private` is file scope.
    static func destination(_ value: Any?) -> String? {
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
    ///
    /// Nothing here splits by line: `markdown(from:)` did that and calls `emit` once per line, so
    /// no section reaching this can span a terminator.
    ///
    /// `shielded` travels on only to the section that *is* the whole of `range`: only that one has
    /// the caller's pair against both of its ends with none of this range's own characters in
    /// between. See `delimiter(for:around:in:as:shielded:)`.
    private static func wrap(
        _ range: NSRange, of text: NSAttributedString, in traits: ArraySlice<Emphasis>,
        as pass: Pass, shielded: Bool = false
    ) -> String {
        guard let trait = traits.first else { return content(range, of: text, as: pass) }
        let rest = traits.dropFirst()

        return MarkdownSlicing.sections(of: range, in: text, carrying: trait)
            .reduce(into: "") { markdown, section in
                let flush = shielded && NSEqualRanges(section.range, range)

                markdown +=
                    section.isOn
                    ? delimited(section.range, of: text, in: traits, as: pass, shielded: flush)
                    : wrap(section.range, of: text, in: rest, as: pass, shielded: flush)
            }
    }

    /// One line's worth of a run, with the pair written around its non-whitespace core.
    ///
    /// The list marker stays outside the pair: `**- [ ] task**` is not a line
    /// `ListContinuation.markerLength` recognises, and since both the characters and the traits
    /// survive that spelling the check accepts it — so the note silently stops being a task.
    ///
    /// Takes the whole of `traits` rather than its head and tail separately: the pair written here
    /// is the first one's, and the rest go inside it.
    private static func delimited(
        _ line: NSRange, of text: NSAttributedString, in traits: ArraySlice<Emphasis>,
        as pass: Pass, shielded: Bool = false
    ) -> String {
        guard let trait = traits.first else { return content(line, of: text, as: pass) }
        let rest = traits.dropFirst()

        let source = text.string as NSString
        let marker = MarkdownSlicing.markerPrefix(of: line, endingAt: pass.markerEnd)
        let core = MarkdownSlicing.trimmed(
            NSRange(location: line.location + marker, length: line.length - marker), in: source)

        // Nothing to put a pair around: whitespace has to stay outside one, so an all-whitespace
        // run is written as the characters it is. A `.dropped` spelling ends up here too.
        //
        // The caller's shield reaches this pair only when the pair goes where the line does: a
        // marker or trimmed whitespace written before it puts a character of the note in between.
        guard core.length > 0,
            let delimiter = delimiter(
                for: trait, around: core, in: source, as: pass.spelling,
                shielded: shielded && NSEqualRanges(core, line))
        else {
            return content(line, of: text, as: pass)
        }

        let before = NSRange(location: line.location, length: core.location - line.location)
        let after = NSRange(
            location: NSMaxRange(core), length: NSMaxRange(line) - NSMaxRange(core))

        // Whatever `rest` writes around the whole of `core` is written between this pair, so it is
        // shielded by it — the `_` of `the **_hard_**ware` is against an asterisk, not the `e`.
        return content(before, of: text, as: pass)
            + delimiter
            + wrap(core, of: text, in: rest, as: pass, shielded: true)
            + delimiter
            + content(after, of: text, as: pass)
    }

    /// Which pair to write around `core`, or nil to write no pair and drop the trait.
    ///
    /// Only italic ever has a choice to make, and only where `_` would not read back. `_` is the
    /// quieter character and the one the parser guards with the word-boundary rule that keeps
    /// `AWS_SECRET_KEY` a name, so the ladder spends both of its permissive rungs on it before
    /// reaching for `*`.
    ///
    /// `shielded` is the caller saying it has already written a pair immediately outside this one,
    /// which settles the boundary question `mayClose` can only guess at: the delimiter beside this
    /// one is not a word character, whatever the rendered text had there. `.fallback` must not reach
    /// for `*` there — `***hard***` is the one place `*` reads worse than `_`, since no parser
    /// resolves a run of three.
    ///
    /// It deliberately does not reprieve `.dropped`: the retreat has to stay monotone, or a shielded
    /// pair that still fails to read back is written again by every rung and takes the line all the
    /// way to `Spelling.plain`, where a link loses its destination.
    private static func delimiter(
        for trait: Emphasis, around core: NSRange, in source: NSString, as spelling: Spelling,
        shielded: Bool = false
    ) -> String? {
        guard !mayClose(trait, around: core, in: source) else { return trait.delimiter }

        switch spelling.italic {
        case .preferred: return trait.delimiter
        case .fallback: return shielded ? trait.delimiter : MarkdownSyntax.emphasisAlternate
        case .dropped: return nil
        }
    }

    /// Whether a `_` pair written around `core` could be one `MarkdownSyntax` reads as italic,
    /// judged on the neighbours it has in the rendered text. True for every other trait, whose
    /// delimiters mind no boundaries — see `MarkdownSyntax.isWordCharacter`.
    ///
    /// A lower bound, not an answer: the delimiters this writer is about to put between `core` and
    /// those neighbours are not here to be seen, so a pair that would have read back can still be
    /// refused. Which is why a refusal decides nothing on its own — `Spelling.Italic` is what it
    /// costs, and each rung of the ladder pays more than the last.
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

    // MARK: - Characters

    /// The user's own characters, with a backslash in front of every one that would otherwise be
    /// read as syntax.
    ///
    /// All of them or none of them, decided per line by the check above. Escaping only the
    /// characters that happen to be part of a construct *this* time would leave the result
    /// depending on what the parser found, which is the thing being defended against.
    ///
    /// The list marker at the head of a line is the exception: `- [ ] ` is content, not syntax this
    /// is defending against, and a backslash through it demotes the checkbox to a bare bullet in
    /// the stored file, leaving `⌘⇧U` nothing to toggle. A link's label is not such a line — see `emit`.
    private static func content(
        _ range: NSRange, of text: NSAttributedString, as pass: Pass
    ) -> String {
        let source = text.string as NSString
        let range = MarkdownSlicing.aligned(range, in: source)
        guard range.length > 0 else { return "" }
        guard pass.spelling.escaping else { return source.substring(with: range) }

        let marker = MarkdownSlicing.markerPrefix(of: range, endingAt: pass.markerEnd)
        let rest = NSRange(
            location: range.location + marker, length: range.length - marker)

        return source.substring(with: NSRange(location: range.location, length: marker))
            + source.substring(with: rest).reduce(into: "") { escaped, character in
                if MarkdownSyntax.isEscapable(character) { escaped.append(MarkdownSyntax.escape) }
                escaped.append(character)
            }
    }
}
