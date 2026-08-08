import Foundation

/// What `⌘B`, `⌘I` and `⌘⇧X` do now that a note is markdown: put the delimiter run around the
/// selection, or take it off again.
///
/// Pure string work, like `ListContinuation` — the rule is the part worth testing, and applying
/// the edit belongs to the platform text views, which are what put it on the undo stack.
///
/// Every command is its own inverse, and it is the *vocabulary* that makes that true rather than
/// any cleverness here. `MarkdownSyntax` spells italic `_`, not `*`, so no delimiter is a prefix
/// of any other and every run belongs unambiguously to one command. When italic was `*`, `⌘I`
/// inside `**bold**` had to guess whether the asterisk it found was its own or half of the bold
/// pair — it first guessed wrong and peeled the pair apart, then, once guarded, grew the run
/// without ever shrinking it again (#117). Disjoint delimiters leave nothing to guess.
enum MarkdownFormatting {
    enum Emphasis: CaseIterable {
        case strong
        case emphasis
        case strikethrough

        var delimiter: String {
            switch self {
            case .strong: MarkdownSyntax.strong
            case .emphasis: MarkdownSyntax.emphasis
            case .strikethrough: MarkdownSyntax.strikethrough
            }
        }
    }

    /// The edit that toggles `emphasis` over `selectedRange`.
    ///
    /// The selection is first trimmed to its non-whitespace core, because `MarkdownSyntax` will
    /// not close a delimiter against whitespace: wrapping a selection with a trailing space
    /// verbatim produced `**bold **`, which renders as four literal asterisks and which no
    /// command could then take off again.
    ///
    /// An empty selection inserts an empty pair and puts the caret between the halves, so `⌘B`
    /// then typing is bold — the same thing it did when it moved typing attributes.
    static func toggle(
        _ emphasis: Emphasis, in text: NSString, selectedRange: NSRange
    ) -> TextEdit {
        let core = trimmed(selectedRange, in: text)

        guard core.length > 0 else {
            // Length zero rather than the selection: a selection of nothing but spaces would
            // otherwise have those spaces replaced by the pair and quietly deleted.
            let caret = selectedRange.location
            let empty = NSRange(location: caret, length: 0)

            // Mid-word the pair would never be read back, and what is typed between the halves
            // would not be either — `key_x_store` is a name, not italic text.
            guard canWrap(emphasis, around: empty, in: text) else {
                return TextEdit(range: empty, replacement: "", selection: selectedRange)
            }

            return TextEdit(
                range: empty,
                replacement: emphasis.delimiter + emphasis.delimiter,
                selection: NSRange(location: caret + emphasis.delimiter.utf16.count, length: 0))
        }

        if spansLines(core, in: text) {
            return toggleAcrossLines(emphasis, over: core, in: text)
        }

        return toggleOnOneLine(emphasis, over: core, in: text)
    }

    // MARK: - One line

    private static func toggleOnOneLine(
        _ emphasis: Emphasis, over core: NSRange, in text: NSString
    ) -> TextEdit {
        let run = run(emphasis, around: core, in: text)

        // Nothing to take off and no way to put one on that the parser would read back: ⌘I in
        // the middle of `keystore` would write `_key_store`, two literal underscores that no
        // later press could tell from the ones in `AWS_SECRET_KEY`. Declining is the only answer
        // that keeps the vocabulary honest.
        guard run.width > 0 || canWrap(emphasis, around: core, in: text) else {
            return TextEdit(range: core, replacement: text.substring(with: core),
                            selection: core)
        }

        let outer = NSRange(
            location: run.core.location - run.width, length: run.core.length + 2 * run.width)

        // Present becomes absent and absent becomes present. That is the whole rule.
        let marks = run.width > 0 ? "" : emphasis.delimiter

        return TextEdit(
            range: outer,
            replacement: marks + text.substring(with: run.core) + marks,
            selection: NSRange(
                location: outer.location + marks.utf16.count, length: run.core.length))
    }

    /// This command's delimiter run around the selection, and the text inside it.
    ///
    /// Two shapes reach here, and both have to give the same answer or the commands stop being
    /// their own inverse: the selection can *be* the whole run (`**keys**` selected end to end),
    /// or it can be the text with the run just outside it (`keys` selected inside `**keys**`,
    /// which is where wrapping leaves the selection). A width of zero means neither — nothing to
    /// take off, so the caller puts one on.
    private static func run(
        _ emphasis: Emphasis, around selection: NSRange, in text: NSString
    ) -> (core: NSRange, width: Int) {
        let delimiter = emphasis.delimiter
        let width = delimiter.utf16.count

        // Delimiters the selection took in. Only when something is left over to style: `****`
        // selected whole is an empty pair, which is a thing to wrap, not a run to unwrap.
        let inner = NSRange(location: selection.location, length: width)
        let innerClose = NSRange(location: NSMaxRange(selection) - width, length: width)
        if selection.length > 2 * width,
            pairs(emphasis, opening: inner, closing: innerClose, in: text) {
            return (
                NSRange(location: selection.location + width, length: selection.length - 2 * width),
                width
            )
        }

        // Delimiters just outside it.
        let before = NSRange(location: selection.location - width, length: width)
        let after = NSRange(location: NSMaxRange(selection), length: width)
        if pairs(emphasis, opening: before, closing: after, in: text) {
            return (selection, width)
        }

        return (selection, 0)
    }

    /// Whether `opening` and `closing` hold this command's delimiters, spelled the way the parser
    /// would read them.
    private static func pairs(
        _ emphasis: Emphasis, opening: NSRange, closing: NSRange, in text: NSString
    ) -> Bool {
        guard opening.location >= 0, NSMaxRange(closing) <= text.length else { return false }

        let delimiter = emphasis.delimiter
        return text.substring(with: opening) == delimiter
            && text.substring(with: closing) == delimiter
            && reads(emphasis, opening: opening.location, closing: closing.location, in: text)
    }

    private static func width(_ emphasis: Emphasis) -> Int { emphasis.delimiter.utf16.count }

    /// Whether a pair opening at `opening` and closing at `closing` is one `MarkdownSyntax` would
    /// read as this command's delimiters. Only `_` can fail: it is a word character in every
    /// identifier a scratchpad holds, so the underscores in `AWS_SECRET_KEY` belong to the name
    /// and not to ⌘I.
    private static func reads(
        _ emphasis: Emphasis, opening: Int, closing: Int, in text: NSString
    ) -> Bool {
        guard MarkdownSyntax.mindsWordBoundaries(emphasis.delimiter) else { return true }

        let before = opening - 1
        let after = closing + width(emphasis)

        if before >= 0, MarkdownSyntax.isWordCharacter(text.character(at: before)) { return false }
        if after < text.length, MarkdownSyntax.isWordCharacter(text.character(at: after)) {
            return false
        }
        return true
    }

    /// Whether a pair *written* around `core` is one the parser would read back. The flanks are
    /// the characters already either side of the selection: the delimiters are not there yet.
    private static func canWrap(
        _ emphasis: Emphasis, around core: NSRange, in text: NSString
    ) -> Bool {
        guard MarkdownSyntax.mindsWordBoundaries(emphasis.delimiter) else { return true }

        let before = core.location - 1
        if before >= 0, MarkdownSyntax.isWordCharacter(text.character(at: before)) { return false }

        let after = NSMaxRange(core)
        if after < text.length, MarkdownSyntax.isWordCharacter(text.character(at: after)) {
            return false
        }

        return true
    }

    // MARK: - Several lines

    /// Wraps or unwraps each line the selection touches, one delimiter run per line.
    ///
    /// A construct never spans lines, so `**line one\nline two**` is markdown the parser will
    /// never read — selecting a paragraph and pressing `⌘B` used to produce exactly that. The
    /// direction is decided once for the whole selection, by whether every line is already
    /// wrapped, which is what keeps a second press undoing the first.
    private static func toggleAcrossLines(
        _ emphasis: Emphasis, over core: NSRange, in text: NSString
    ) -> TextEdit {
        let lines = lineContents(in: text, over: core)
        guard let first = lines.first, let last = lines.last else {
            return TextEdit(range: core, replacement: text.substring(with: core))
        }

        let runs = lines.map { run(emphasis, around: $0, in: text) }
        let wrapped = runs.allSatisfy { $0.width > 0 }

        let span = NSRange(location: first.location, length: NSMaxRange(last) - first.location)
        var replacement = ""
        var cursor = span.location

        for (line, run) in zip(lines, runs) {
            // Whatever sits between one line's content and the next — the newline, and any
            // indentation — is carried over untouched.
            replacement += text.substring(
                with: NSRange(location: cursor, length: line.location - cursor))

            let marks = wrapped ? "" : emphasis.delimiter
            replacement += marks + text.substring(with: run.core) + marks

            cursor = NSMaxRange(line)
        }

        return TextEdit(
            range: span,
            replacement: replacement,
            selection: NSRange(location: span.location, length: (replacement as NSString).length))
    }

    /// The non-whitespace content of every line the range touches, in order, skipping blank ones.
    ///
    /// A range that starts or ends mid-line takes in the whole of that line: the delimiters have
    /// to end up around a line's content, not around the part of it that happened to be selected.
    private static func lineContents(in text: NSString, over range: NSRange) -> [NSRange] {
        var contents: [NSRange] = []
        var cursor = range.location

        while cursor < NSMaxRange(range) {
            let line = text.lineRange(for: NSRange(location: cursor, length: 0))
            guard line.length > 0 else { break }

            let content = trimmed(line, in: text)
            if content.length > 0 { contents.append(content) }

            cursor = NSMaxRange(line)
        }

        return contents
    }

    // MARK: - Scanning

    /// `range` with leading and trailing whitespace dropped.
    private static func trimmed(_ range: NSRange, in text: NSString) -> NSRange {
        var start = range.location
        var end = NSMaxRange(range)

        while start < end, MarkdownSyntax.isWhitespace(text.character(at: start)) { start += 1 }
        while end > start, MarkdownSyntax.isWhitespace(text.character(at: end - 1)) { end -= 1 }

        return NSRange(location: start, length: end - start)
    }

    private static func spansLines(_ range: NSRange, in text: NSString) -> Bool {
        text.rangeOfCharacter(from: .newlines, options: [], range: range).location != NSNotFound
    }
}
