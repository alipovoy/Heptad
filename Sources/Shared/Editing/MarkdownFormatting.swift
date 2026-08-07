import Foundation

/// What `⌘B`, `⌘I` and `⌘⇧X` do now that a note is markdown: wrap the selection in delimiters,
/// or take them off again.
///
/// Pure string work, like `ListContinuation` — the rule is the part worth testing, and applying
/// the edit belongs to the platform text views, which are what put it on the undo stack.
///
/// Every command is its own inverse. That is the property the old attribute-mutating path could
/// not offer for everything it let into a note (#117): here, whatever `⌘B` can add, a second
/// `⌘B` can take away.
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
    /// Three cases, in the order they are checked:
    ///
    /// 1. The selection *is* the delimited run (`**bold**` selected whole) — unwrap it.
    /// 2. The delimiters sit just outside the selection (`bold` selected inside `**bold**`) —
    ///    unwrap it. This is the one that makes a second `⌘B` undo the first, because wrapping
    ///    leaves the inner text selected.
    /// 3. Otherwise wrap.
    ///
    /// An empty selection inserts an empty pair and puts the caret between the halves, so `⌘B`
    /// then typing is bold — the same thing it did when it moved typing attributes.
    static func toggle(_ emphasis: Emphasis, in text: NSString, selectedRange: NSRange)
        -> TextEdit
    {
        let delimiter = emphasis.delimiter
        let width = delimiter.utf16.count

        guard selectedRange.length > 0 else {
            return TextEdit(
                range: selectedRange,
                replacement: delimiter + delimiter,
                selection: NSRange(location: selectedRange.location + width, length: 0))
        }

        let selected = text.substring(with: selectedRange)

        if selected.utf16.count > 2 * width,
            selected.hasPrefix(delimiter), selected.hasSuffix(delimiter),
            !doubled(delimiter, adjacentTo: String(selected.dropFirst(width).dropLast(width)))
        {
            let inner = String(selected.dropFirst(width).dropLast(width))
            return TextEdit(
                range: selectedRange,
                replacement: inner,
                selection: NSRange(location: selectedRange.location, length: inner.utf16.count))
        }

        let outer = NSRange(
            location: selectedRange.location - width, length: selectedRange.length + 2 * width)
        if outer.location >= 0, NSMaxRange(outer) <= text.length,
            text.substring(with: outer) == delimiter + selected + delimiter,
            !surrounded(by: delimiter, outside: outer, in: text)
        {
            return TextEdit(
                range: outer,
                replacement: selected,
                selection: NSRange(location: outer.location, length: selectedRange.length))
        }

        return TextEdit(
            range: selectedRange,
            replacement: delimiter + selected + delimiter,
            selection: NSRange(
                location: selectedRange.location + width, length: selectedRange.length))
    }

    // MARK: - Telling `*` apart from `**`
    //
    // `*` is a prefix of `**`, so an unwrap that only looks one delimiter out reads the inner
    // half of a bold pair as its own emphasis run. Left unchecked, ⌘I inside `**keys**` peeled
    // one asterisk off each side and quietly turned the bold into italic. The two checks below
    // decline that match, so the command wraps instead and each delimiter stays the business of
    // the command that writes it.

    /// Whether a longer run of `delimiter` continues just inside what looked like a pair.
    private static func doubled(_ delimiter: String, adjacentTo inner: String) -> Bool {
        delimiter == MarkdownSyntax.emphasis
            && (inner.hasPrefix(delimiter) || inner.hasSuffix(delimiter))
    }

    /// Whether a longer run of `delimiter` continues just outside what looked like a pair.
    private static func surrounded(by delimiter: String, outside range: NSRange, in text: NSString)
        -> Bool
    {
        guard delimiter == MarkdownSyntax.emphasis else { return false }

        let width = delimiter.utf16.count
        let before = NSRange(location: range.location - width, length: width)
        let after = NSRange(location: NSMaxRange(range), length: width)

        let precededByMore = before.location >= 0
            && text.substring(with: before) == delimiter
        let followedByMore = NSMaxRange(after) <= text.length
            && text.substring(with: after) == delimiter

        return precededByMore || followedByMore
    }
}
