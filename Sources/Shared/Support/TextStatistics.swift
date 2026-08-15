import Foundation
import Observation

/// The counts the editors produce and the statistics bar shows, held in an object rather than
/// in `ContentView`'s own state.
///
/// As `@State` on the root view these re-evaluated the entire tree on every keystroke — the
/// macOS title bar, all seven colour circles, the background fill and the representable's
/// `updateNSView` — to move three numbers in the bar at the bottom. `@Observable` tracking is
/// per property read, so only the view that actually reads `stats` is invalidated.
///
/// It is also what the editor coordinators write through. A coordinator outlives every
/// `NSViewRepresentable` struct that drives it, so reaching the binding used to mean holding a
/// back-reference to that struct and refreshing it on each update (#47); a reference type is
/// simply the same object throughout.
@MainActor
@Observable
final class EditorStatistics {
    var stats: TextStats

    init(stats: TextStats = .zero) {
        self.stats = stats
    }
}

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
                if Self.isNewline(scalar) { lines += 1 }

                // A word is a maximal run of alphanumerics, which is the same thing as a
                // non-empty component of a split on everything else.
                if Self.isAlphanumeric(scalar) {
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

    /// The two membership tests, spelled without `CharacterSet`.
    ///
    /// `CharacterSet.contains` was the whole cost of this: the same counts came out twice as fast
    /// on every size measured, 9.8 ms → 5.3 ms for a 145 KB note. The answers are unchanged —
    /// these are the same two sets, written as the ranges they are.
    private static func isNewline(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0A...0x0D, 0x85, 0x2028, 0x2029: true
        default: false
        }
    }

    /// ASCII first, because notes are mostly ASCII and the property lookup is what costs.
    /// Everything above it defers to Unicode's own answer, which is what `.alphanumerics`
    /// documents itself as.
    ///
    /// Not quite what it *answered*, though: Foundation's tables lag the ones
    /// `Unicode.Scalar.Properties` reads, so scalars it has not caught up with — Tangut, Todhri —
    /// were letters to Unicode and not to it. They count as words now. That is the only direction
    /// the two differ in, and it is the newer answer.
    private static func isAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A: return true
        case ..<0x80: return false
        default: break
        }

        // Letters, marks and numbers — `CharacterSet.alphanumerics` is L* ∪ M* ∪ N*, and the marks
        // are the half that is easy to miss: a decomposed `é` is a letter followed by a combining
        // accent, and dropping the accent from the set cuts the word in two.
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
            .nonspacingMark, .spacingMark, .enclosingMark,
            .decimalNumber, .letterNumber, .otherNumber:
            return true
        default:
            return false
        }
    }
}
