import Foundation

/// The markdown Heptad understands. Where it occurs in a note's text is `MarkdownScanning`.
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
    /// markdown parser, and `⌘I` has to be writable wherever the caret is. `*` minds no boundaries,
    /// so it covers exactly those.
    ///
    /// Read here, but written only as `MarkdownWriting`'s fallback, because text is full of loose
    /// asterisks. They stay ordinary because a delimiter never opens against whitespace — `2 * 3`
    /// and `SELECT * FROM` mean what they say — and `**` is matched before `*` is tried.
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

    // MARK: - Character classes
    //
    // Here rather than beside the scan that uses them most, because the writer and the commands
    // share them: a second spelling of "word character" or "whitespace" would let this app emit
    // markdown it does not read back the same way.

    /// `MarkdownWriting` asks this when it chooses between `_` and `*`, so the pair it writes is
    /// one the scanner reads back.
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

    /// The commands and the writer trim to the same idea of whitespace the scanner refuses to
    /// close a delimiter against, so neither can emit markdown it would reject.
    static func isWhitespace(_ character: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(character) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }

    /// Shared for the same reason as `isWhitespace`: the writer keeps a construct off a line's
    /// terminator, so it has to agree with the scanner about where one is.
    static func isNewline(_ character: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(character) else { return false }
        return CharacterSet.newlines.contains(scalar)
    }
}
