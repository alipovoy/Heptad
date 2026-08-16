import Foundation
import Testing

@testable import Heptad

/// One case of the counting contract: an input and the three numbers the status readout
/// shows for it.
struct TextStatsCase: Sendable, CustomTestStringConvertible {
    let text: String
    let characters: Int
    let words: Int
    let lines: Int

    var testDescription: String { "\(String(reflecting: text)) → \(characters)/\(words)/\(lines)" }
}

struct TextStatisticsTests {

    /// The counts below are what the implementation produces today, pinned so that three
    /// decisions currently implicit in it cannot regress silently:
    ///
    /// - `characters` excludes newlines, so `"a\nb"` is 2 rather than 3.
    /// - A trailing newline still opens a second line, because `components(separatedBy:)`
    ///   yields a trailing empty element.
    /// - `words` splits on the inverse of `.alphanumerics`, so an apostrophe cuts a word in
    ///   two (`don't` counts as 2) and an emoji counts as no word at all.
    ///
    /// The apostrophe case is arguably wrong for a note-taking app — `"don't stop"` reading
    /// as three words is visible to the user — but changing it is a product decision, not a
    /// test fix. This pins the current behaviour so the change, if it comes, is deliberate.
    @Test(arguments: [
        TextStatsCase(text: "", characters: 0, words: 0, lines: 0),
        TextStatsCase(text: "hello", characters: 5, words: 1, lines: 1),
        TextStatsCase(text: "a\nb", characters: 2, words: 2, lines: 2),
        TextStatsCase(text: "a\n", characters: 1, words: 1, lines: 2),
        TextStatsCase(text: "  ", characters: 2, words: 0, lines: 1),
        TextStatsCase(text: "one  two", characters: 8, words: 2, lines: 1),
        TextStatsCase(text: "don't stop", characters: 10, words: 3, lines: 1),
        TextStatsCase(text: "héllo 👋", characters: 7, words: 1, lines: 1)
    ])
    func countsMatchTheCurrentContract(expected: TextStatsCase) {
        let stats = TextStats(text: expected.text)

        #expect(stats.characters == expected.characters)
        #expect(stats.words == expected.words)
        #expect(stats.lines == expected.lines)
    }

    /// The membership tests still answer exactly what `CharacterSet` answered.
    ///
    /// `.newlines` and `.alphanumerics` were replaced by scalar ranges and a general-category check.
    /// The cases above pin the contract; this pins that the rewrite did not move it, across scripts,
    /// combining marks, line separators and the astral plane a hand-written range list gets wrong.
    @Test(arguments: [
        "", "hello", "a\r\nb", "a\u{2028}b", "a\u{2029}b", "a\u{0B}b\u{0C}c", "a\u{85}b",
        "ümlaut ß Straße", "汉字 test", "e\u{0301}mile", "Ⅻ roman Ⅻ", "٣٤٥ arabic digits",
        "𝕬𝖓𝖙𝖎𝖖𝖚𝖆 astral", "👋🏽 emoji ✅", "_underscore-hyphen.dot", "١٢٣\n٤٥٦"
    ])
    func theScalarTestsAgreeWithCharacterSet(text: String) {
        #expect(TextStats(text: text) == Self.usingCharacterSet(text))
    }

    /// The counting loop as it was, `CharacterSet` and all — the thing the rewrite has to match.
    private static func usingCharacterSet(_ text: String) -> TextStats {
        var stats = TextStats()
        guard !text.isEmpty else { return stats }

        var lines = 1
        var inWord = false

        for character in text {
            if !character.isNewline { stats.characters += 1 }
            for scalar in character.unicodeScalars {
                if CharacterSet.newlines.contains(scalar) { lines += 1 }
                if CharacterSet.alphanumerics.contains(scalar) {
                    if !inWord {
                        stats.words += 1
                        inWord = true
                    }
                } else {
                    inWord = false
                }
            }
        }

        stats.lines = lines
        return stats
    }
}
