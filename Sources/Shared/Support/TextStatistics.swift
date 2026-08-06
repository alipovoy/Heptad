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
