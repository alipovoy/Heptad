import Foundation

struct TextStats: Equatable {
    var characters = 0
    var words = 0
    var lines = 0

    static let zero = Self()

    init() {}

    /// Counts the three numbers in one pass, without allocating.
    ///
    /// This runs off the main actor on every keystroke, over the whole note. The obvious
    /// spelling — `filter`, and `components(separatedBy:)` twice — allocates a `String` per
    /// line and a `String` per word only to count them, which is roughly a thousand throwaway
    /// allocations for a thousand-word note.
    ///
    /// The counts are exactly what those three expressions produced, edge cases included: a
    /// line is opened by each newline *scalar*, so a CRLF opens two, the way
    /// `components(separatedBy: .newlines)` split on both of them — while a character is a
    /// grapheme, so that same CRLF is a single character, and an excluded one.
    init(text: String) {
        guard !text.isEmpty else { return }

        var lines = 1
        var inWord = false

        for character in text {
            if !character.isNewline { characters += 1 }

            for scalar in character.unicodeScalars {
                if Self.newlines.contains(scalar) { lines += 1 }

                // A word is a maximal run of alphanumerics, which is the same thing as a
                // non-empty component of a split on everything else.
                if Self.alphanumerics.contains(scalar) {
                    if !inWord {
                        words += 1
                        inWord = true
                    }
                } else {
                    inWord = false
                }
            }
        }

        self.lines = lines
    }

    /// Hoisted: rebuilding either one per scalar would give back what the loop above saves.
    private static let newlines = CharacterSet.newlines
    private static let alphanumerics = CharacterSet.alphanumerics
}
