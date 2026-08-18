import Foundation

/// Which characters a note is allowed to hold at all.
///
/// `MarkdownSyntax` says what the characters in a note *mean*; this says which ones may be there
/// in the first place. It is the rule the whole markdown swap exists to hold — nothing enters a
/// note that no command can take back out — applied to characters instead of attributes, which is
/// the half `MarkdownStyling.normalize` never covered: it strips a paste's colour, its alignment
/// and its 24pt font, and leaves whatever the paste spelled those with in the text.
///
/// Two kinds get in that way. An `NSTextAttachment` contributes U+FFFC to a string, so copying an
/// image and a word of bold out of Mail brings one along: invisible, not selectable as anything,
/// and it survives every save from then on. A C0 control is the same passenger with a worse
/// effect in a text view — a NUL, or the `\r` of a Windows line ending pretending to be a line of
/// its own.
///
/// `\n` and `\t` are the exceptions, because they are text: one ends a line, and the other is in
/// every snippet of indented code anyone pastes.
enum NoteCharacters {
    /// Whether a note may hold `character`. Written against UTF-16 units because that is what the
    /// writer has: every character this drops is one unit, so no surrogate pair can be split by
    /// asking one half at a time.
    static func isStorable(_ character: unichar) -> Bool {
        !isDiscarded(UInt32(character))
    }

    /// `text` with everything a note may not hold taken out.
    ///
    /// Scalar by scalar rather than character by character, so a `\r\n` loses its `\r` and keeps
    /// its `\n` — as one grapheme it would go whole, and the paste would lose the line break.
    static func storable(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: { isDiscarded($0.value) }) else { return text }

        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars where !isDiscarded(scalar.value) { scalars.append(scalar) }

        return String(scalars)
    }

    private static func isDiscarded(_ value: UInt32) -> Bool {
        switch value {
        case 0x09, 0x0A: false
        case 0x00...0x1F, 0x7F: true
        case 0xFFFC: true
        default: false
        }
    }
}
