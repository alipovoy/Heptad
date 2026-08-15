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
    /// Something has to be unconditional, or a line the check rejects twice is written rejected —
    /// which is how a link this app cannot spell used to change the note's own text. **A save may
    /// lose formatting; it may never lose a character.** The one exception is what a note may not
    /// hold at all: `NoteCharacters` says which, taken out before any of this runs.
    ///
    /// Per line, because escapes are noise in the source and a note is read in that mode too: a
    /// line that needs them gets them, and the rest of the note stays as clean as it reads.
    static func markdown(from attributed: NSAttributedString) -> String {
        let attributed = storable(attributed)
        let whole = NSRange(location: 0, length: attributed.length)

        return MarkdownSlicing.lines(of: whole, in: attributed).reduce(into: "") { markdown, line in
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

    /// `attributed` without the characters a note may not hold, and the same object when there
    /// are none.
    ///
    /// Taken out here rather than as each slice is written, so every index the check compares
    /// still lines up: a line whose attachment placeholder went missing between the writing and
    /// the reading looks like a line the writer got wrong, and would be sent to a candidate that
    /// keeps nothing.
    private static func storable(_ attributed: NSAttributedString) -> NSAttributedString {
        let source = attributed.string as NSString
        let discarded = (0..<source.length)
            .filter { !NoteCharacters.isStorable(source.character(at: $0)) }
        guard !discarded.isEmpty else { return attributed }

        let filtered = NSMutableAttributedString(attributedString: attributed)
        for index in discarded.reversed() {
            filtered.deleteCharacters(in: NSRange(location: index, length: 1))
        }

        return filtered
    }

    /// How hard one candidate line tries, and the order they are tried in.
    ///
    /// Two independent retreats, because they give up different things. Escaping costs the source
    /// its cleanliness; caution costs the note a trait. Neither is worth spending until the
    /// spelling that keeps both has been written and rejected.
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

            /// Write no pair, and lose the trait. What is left when `*` will not read back
            /// either — the corner where the pair lands inside a `**` one, since `**Test*ing***`
            /// is a run of asterisks no parser resolves as this meant it. The choice by then is
            /// between dropping this trait and dropping every trait on the line.
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

    // MARK: - Checking

    /// Whether `markdown` reads back as the text it was written from: the same characters, and no
    /// formatting on them the text did not already have.
    ///
    /// The characters alone are not enough. `a***b**` has exactly the characters of `a*` followed
    /// by a bold `b`, and reads back as a bold `*b`; only comparing the formatting catches it.
    ///
    /// Asymmetric on purpose, and this is the half that is easy to get wrong. Formatting the
    /// writer *cannot spell* is dropped by design — the rules at the top of this file are all
    /// losses — so a check that called those failures would reject the writer's own correct
    /// output and send the line to a candidate that keeps less. What must never pass is the other
    /// direction: emphasis on characters that never carried it, which is why escaping exists.
    private static func reads(_ markdown: String, as original: NSAttributedString) -> Bool {
        let rendered = RichTextRendering.attributed(from: markdown, appearance: reading)

        // Lengths as well as characters, and the lengths first: `String ==` is canonical
        // equivalence while `length` counts UTF-16 units, and the two disagree — `\u{1100}\u{1161}`
        // equals `\u{AC00}` at lengths 2 and 1. Nothing on this path renormalizes, so the loop
        // below was never actually reading past the end of `original`; this is what makes its
        // bound correct by construction rather than by that argument.
        guard rendered.length == original.length, rendered.string == original.string else {
            return false
        }

        // Walked by run, not by character: both strings answer alike over the overlap of a run
        // in each, so asking per UTF-16 unit asked the same two dictionaries over and over —
        // 63,160 lookups for a 15,790-unit note of ~1,200 runs, 32 ms of a 128 ms save.
        var index = 0
        while index < rendered.length {
            var readRun = NSRange(location: 0, length: 0)
            let read = rendered.attributes(at: index, effectiveRange: &readRun)

            var intendedRun = NSRange(location: 0, length: 0)
            _ = original.attributes(at: index, effectiveRange: &intendedRun)

            // The last unit of the overlap is asked on its own, because it is the only one whose
            // *neighbour* can carry something else — and `intent` reads that neighbour, for the
            // surrogate pair whose halves were given different attributes. Everywhere before it,
            // the neighbour is inside this same run and adds nothing.
            let step = min(NSMaxRange(readRun), NSMaxRange(intendedRun))
            if step - 1 > index, !justifies(intent(of: original, at: index), read) { return false }
            if !justifies(intent(of: original, at: step - 1), read) { return false }

            index = step
        }

        return true
    }

    /// Whether what the note meant at a position can account for what was read back at it.
    /// One-way, for the reason `reads` gives.
    private static func justifies(
        _ intended: [[NSAttributedString.Key: Any]], _ read: [NSAttributedString.Key: Any]
    ) -> Bool {
        let link = destination(read[.link])

        return Emphasis.allCases.allSatisfy { trait in
            !trait.isOn(read) || intended.contains(where: trait.isOn)
        } && (link == nil || intended.contains { link == destination($0[.link]) })
    }

    /// What the note means the character at `index` to carry — both halves of it, when it has two.
    ///
    /// A surrogate pair is one character across two indices, and an attribute may start between
    /// them. `MarkdownSlicing.aligned` moves the writer's boundaries off that split, so the lead
    /// half comes back carrying what the trail half was given; reading that as formatting
    /// appearing out of nowhere would send the line to a candidate that keeps less.
    private static func intent(
        of original: NSAttributedString, at index: Int
    ) -> [[NSAttributedString.Key: Any]] {
        var halves = [original.attributes(at: index, effectiveRange: nil)]
        let source = original.string as NSString

        if index + 1 < source.length, UTF16.isLeadSurrogate(source.character(at: index)) {
            halves.append(original.attributes(at: index + 1, effectiveRange: nil))
        }

        return halves
    }

    /// The appearance the check reads with. Only traits are compared and traits carry no size,
    /// so the note's own zoom never has to reach this file.
    private static let reading = MarkdownStyling.Appearance(
        plainText: false, fontSize: AppConstants.Layout.defaultFontSize)

    // MARK: - Links

    /// Links first, because a label is not parsed: `[**a**](b)` reads literally, so whatever is
    /// inside one is written as plain characters. Emphasis over a link is written *around* it —
    /// `**[docs](url)**`, the spelling the parser already reads.
    private static func emit(
        _ range: NSRange, of text: NSAttributedString, as spelling: Spelling
    ) -> String {
        guard range.length > 0 else { return "" }
        let source = text.string as NSString

        var markdown = ""
        text.enumerateAttribute(.link, in: range, options: []) { value, subrange, _ in
            // The terminator is not part of the label. A link carrying one reaches the end of
            // its line rather than spanning two, and writing the `\n` inside the brackets is what
            // used to drop it everywhere but the note's last line, which has none to carry.
            let core = MarkdownSlicing.withoutTerminator(subrange, in: source)

            guard let destination = destination(value), core.length > 0 else {
                markdown += wrap(subrange, of: text, in: Emphasis.allCases, as: spelling)
                return
            }

            let terminator = NSRange(
                location: NSMaxRange(core), length: NSMaxRange(subrange) - NSMaxRange(core))

            // The destination is written as it is: a URL holding a bracket of its own cannot be
            // spelled either way, and escaping there would move the problem into the address.
            let traits = uniform(over: core, in: text)
            markdown += traits.map(\.delimiter).joined()
                + "[" + content(core, of: text, as: spelling) + "](" + destination + ")"
                + traits.reversed().map(\.delimiter).joined()
                + content(terminator, of: text, as: spelling)
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
    ///
    /// Nothing here splits by line: `markdown(from:)` did that and calls `emit` once per line, so
    /// no section reaching this can span a terminator. A second split used to sit on the `isOn`
    /// branch — instrumented at 9 of 9 sections returning a single range.
    private static func wrap(
        _ range: NSRange, of text: NSAttributedString, in traits: [Emphasis],
        as spelling: Spelling
    ) -> String {
        guard let trait = traits.first else { return content(range, of: text, as: spelling) }
        let rest = Array(traits.dropFirst())

        return MarkdownSlicing.sections(of: range, in: text, carrying: trait)
            .reduce(into: "") { markdown, section in
                markdown +=
                    section.isOn
                    ? delimited(section.range, of: text, with: trait, then: rest, as: spelling)
                    : wrap(section.range, of: text, in: rest, as: spelling)
            }
    }

    /// One line's worth of a run, with the pair written around its non-whitespace core.
    private static func delimited(
        _ line: NSRange, of text: NSAttributedString, with trait: Emphasis, then rest: [Emphasis],
        as spelling: Spelling
    ) -> String {
        let source = text.string as NSString
        let core = MarkdownSlicing.trimmed(line, in: source)

        // Nothing to put a pair around: whitespace has to stay outside one, so a run that is all
        // whitespace is written as the characters it is. A `.dropped` spelling ends up here too,
        // for the italics it has given up on.
        guard core.length > 0,
            let delimiter = delimiter(for: trait, around: core, in: source, as: spelling)
        else {
            return content(line, of: text, as: spelling)
        }

        let before = NSRange(location: line.location, length: core.location - line.location)
        let after = NSRange(
            location: NSMaxRange(core), length: NSMaxRange(line) - NSMaxRange(core))

        return content(before, of: text, as: spelling)
            + delimiter
            + wrap(core, of: text, in: rest, as: spelling)
            + delimiter
            + content(after, of: text, as: spelling)
    }

    /// Which pair to write around `core`, or nil to write no pair and drop the trait.
    ///
    /// Only italic ever has a choice to make, and only where `_` would not read back. `_` is the
    /// quieter character and the one the parser guards with the word-boundary rule that keeps
    /// `AWS_SECRET_KEY` a name, so the ladder spends both of its permissive rungs on it before
    /// reaching for `*`. Before `*` was written at all, those runs were dropped — which is why
    /// `⌘I` mid-word showed italic that the next save took away.
    private static func delimiter(
        for trait: Emphasis, around core: NSRange, in source: NSString, as spelling: Spelling
    ) -> String? {
        guard !mayClose(trait, around: core, in: source) else { return trait.delimiter }

        switch spelling.italic {
        case .preferred: return trait.delimiter
        case .fallback: return MarkdownSyntax.emphasisAlternate
        case .dropped: return nil
        }
    }

    /// Whether a `_` pair written around `core` could be one `MarkdownSyntax` reads as italic,
    /// judged on the neighbours it has in the rendered text. True for every other trait, whose
    /// delimiters mind no boundaries — see `MarkdownSyntax.isWordCharacter`.
    ///
    /// A lower bound, not an answer: the delimiters this writer is about to put between `core`
    /// and those neighbours are not here to be seen, so a pair that would have read back can
    /// still be refused. Which is why refusing it decides nothing on its own — `Spelling.Italic`
    /// is what a refusal costs, and each rung of the ladder pays more for it than the last.
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
    /// With one exception, and it is not one: the list marker at the head of a line is not
    /// syntax the escaping is defending against. `- [ ] ` is content the user typed or had typed
    /// for them, and a backslash through it demotes the checkbox to a bare bullet in the stored
    /// file — a line that read as a task before the save does not after it, and `⌘⇧U` in plain
    /// mode then has nothing to toggle.
    private static func content(
        _ range: NSRange, of text: NSAttributedString, as spelling: Spelling
    ) -> String {
        let source = text.string as NSString
        let range = MarkdownSlicing.aligned(range, in: source)
        guard range.length > 0 else { return "" }
        guard spelling.escaping else { return source.substring(with: range) }

        let marker = MarkdownSlicing.markerPrefix(of: range, in: source)
        let rest = NSRange(
            location: range.location + marker, length: range.length - marker)

        return source.substring(with: NSRange(location: range.location, length: marker))
            + source.substring(with: rest).reduce(into: "") { escaped, character in
                if MarkdownSyntax.isEscapable(character) { escaped.append(MarkdownSyntax.escape) }
                escaped.append(character)
            }
    }
}
