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
}
