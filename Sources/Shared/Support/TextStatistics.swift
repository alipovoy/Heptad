import Foundation

struct TextStats: Equatable {
    var characters = 0
    var words = 0
    var lines = 0

    static let zero = Self()

    init() {}

    init(text: String) {
        // Characters count (excluding newlines)
        characters = text.filter { !$0.isNewline }.count

        // Lines count (empty string is 0 lines, otherwise at least 1)
        lines = text.isEmpty ? 0 : text.components(separatedBy: .newlines).count

        // Words count
        // Separating by inverted alphanumerics ensures only alphanumeric words are counted.
        words = text.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .count
    }
}
