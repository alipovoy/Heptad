import Foundation
import SwiftData

#if canImport(UIKit)
    import UIKit
#else
    import AppKit
#endif

@Model
final class NoteItem {
    @Attribute(.unique) var id: Int
    var rtfData: Data

    /// When `rtfData` last changed.
    ///
    /// The default is load-bearing rather than decorative: SwiftData needs one to
    /// lightweight-migrate stores written before this property existed. `.distantPast`
    /// is the honest backfill for those rows — their real edit time was never recorded,
    /// and it keeps them behind every genuinely timestamped note in a recency ordering.
    var modifiedAt: Date = Date.distantPast

    /// Whether the note is edited as plain, monospaced text.
    ///
    /// The store is RTF either way; this only says what the editor may put in it. Same reason
    /// as `modifiedAt` for carrying a default: SwiftData needs one to lightweight-migrate
    /// stores written before the property existed, and rich text is what those notes were.
    var isPlainText: Bool = false

    init(id: Int, rtfData: Data = Data(), modifiedAt: Date = .now, isPlainText: Bool = false) {
        self.id = id
        self.rtfData = rtfData
        self.modifiedAt = modifiedAt
        self.isPlainText = isPlainText
    }
}

/// RTF is the note's single storage format; the editors and the saver all go through these helpers.
extension NoteItem {
    var isEmpty: Bool { rtfData.isEmpty }

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

    /// The note's content decoded from RTF, ready to display, or nil when empty or undecodable.
    ///
    /// Colorless runs get the adaptive text color here, at the one point where stored data
    /// becomes displayable content, so every editor shows them in the system appearance
    /// instead of the black that text layout would otherwise default to.
    var attributedContent: NSAttributedString? {
        guard !rtfData.isEmpty else { return nil }
        let decoded = try? NSAttributedString(
            data: rtfData,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
        return decoded?.fillingInAdaptiveTextColor()
    }

    /// Encodes the attributed string as RTF. Whitespace-only content encodes as
    /// empty data; nil means encoding failed and the previous data should be kept.
    static func rtfData(from attributedString: NSAttributedString) -> Data? {
        // Asking whether any non-whitespace exists, rather than trimming and measuring what is
        // left: this runs on every debounced save, and the trimmed copy was built only to be
        // thrown away.
        let isEmpty = attributedString.length == 0
            || attributedString.string.rangeOfCharacter(
                from: .whitespacesAndNewlines.inverted) == nil
        guard !isEmpty else { return Data() }

        let range = NSRange(location: 0, length: attributedString.length)
        return try? attributedString.data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }
}
