import Foundation

struct TextStats: Equatable {
    var characters: Int = 0
    var words: Int = 0
    var lines: Int = 0

    static let zero = TextStats()
}

class TextStatisticsCalculator {
    /// Calculates text statistics on a background queue and returns via main queue completion.
    static func calculate(for text: String, completion: @escaping (TextStats) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            // Characters count (excluding newlines)
            let characters = text.filter { !$0.isNewline }.count

            // Lines count (empty string is 0 lines, otherwise at least 1)
            let lines = text.isEmpty ? 0 : text.components(separatedBy: .newlines).count

            // Words count
            // Separating by inverted alphanumerics ensures only alphanumeric words are counted.
            let words = text.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .count

            let stats = TextStats(characters: characters, words: words, lines: lines)

            DispatchQueue.main.async {
                completion(stats)
            }
        }
    }
}
