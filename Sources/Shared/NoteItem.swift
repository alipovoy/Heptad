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

    init(id: Int, rtfData: Data = Data()) {
        self.id = id
        self.rtfData = rtfData
    }
}

/// RTF is the note's single storage format; the editors and the saver all go through these helpers.
extension NoteItem {
    var isEmpty: Bool { rtfData.isEmpty }

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
        let isEmpty = attributedString.length == 0
            || attributedString.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard !isEmpty else { return Data() }

        let range = NSRange(location: 0, length: attributedString.length)
        return try? attributedString.data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }
}
