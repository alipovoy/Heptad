import Foundation
import SwiftData

@Model
final class NoteItem {
    @Attribute(.unique) var id: Int

    /// The note, as markdown source.
    ///
    /// A `String`, not an attributed blob. Styling is derived from these characters on every
    /// change and never stored, which is what keeps the editor from holding formatting no
    /// command can remove — see `MarkdownStyling` and #117. It also means a note is exactly what
    /// you see, so copying one out gives back the same text.
    ///
    /// The default is load-bearing rather than decorative, for the same reason as the two
    /// properties below: SwiftData needs one to lightweight-migrate stores written before this
    /// property existed — which is every store written while notes were RTF.
    var text: String = ""

    /// When `text` last changed.
    var modifiedAt: Date = Date.distantPast

    /// Whether the note is shown as plain, monospaced text with its markdown left literal.
    ///
    /// Purely how the note is drawn. Switching modes used to flatten the note's attributes,
    /// which made it a one-way trip; now it changes nothing about the text, so it is reversible
    /// as often as you like.
    var isPlainText: Bool = false

    init(id: Int, text: String = "", modifiedAt: Date = .now, isPlainText: Bool = false) {
        self.id = id
        self.text = text
        self.modifiedAt = modifiedAt
        self.isPlainText = isPlainText
    }
}

extension NoteItem {
    var isEmpty: Bool { text.isEmpty }

    /// The rows a view may address by position — ids `0..<AppConstants.noteCount`, in the order
    /// the store handed them over.
    ///
    /// A note is addressed by its place in this array, so an id outside the range has no place in
    /// it, at either end: letting one through makes the count read seven-plus-one and strands
    /// `ContentView` on its "notes could not be loaded" branch, which nothing gets back off.
    /// Extras are ignored rather than deleted — a store carrying an eighth row still has seven
    /// good notes in it, and they are not a view's to remove.
    static func addressable(in notes: [NoteItem]) -> [NoteItem] {
        notes.filter { (0..<AppConstants.noteCount).contains($0.id) }
    }

    /// When the note was last edited, or nil when there is no edit to report.
    ///
    /// Two cases have a `modifiedAt` that is worse than useless to show. An empty note has
    /// never held anything — `init` stamps it with the time the seven notes were created,
    /// which says nothing about the user. And `.distantPast` is the migration backfill for
    /// rows written before the property existed. Formatting either one puts "2,025 years ago"
    /// or a creation time the user never caused under a blank editor.
    var lastEditedAt: Date? {
        guard !isEmpty, modifiedAt != .distantPast else { return nil }
        return modifiedAt
    }

    /// What a text view's contents are stored as: itself, or "" when there is nothing but
    /// whitespace in it.
    ///
    /// The empty spelling is what `isEmpty` — and so `⌘0`, which finds the first empty note —
    /// reads. A note holding a stray newline is one nobody has written in.
    static func storedText(from text: String) -> String {
        text.rangeOfCharacter(from: .whitespacesAndNewlines.inverted) == nil ? "" : text
    }
}
