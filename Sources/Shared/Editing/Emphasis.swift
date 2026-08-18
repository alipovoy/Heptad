import Foundation

#if canImport(UIKit)
    import UIKit
#else
    import AppKit
#endif

/// The app's whole formatting vocabulary: what `⌘B`, `⌘I` and `⌘⇧X` produce.
///
/// One type, read by everything that has to agree about it — `AttributedFormatting` toggles these
/// on the editor's rich text, `MarkdownWriting` spells them as delimiters on the way to the
/// store, and `MarkdownSyntax` reads those delimiters back. Anything outside this list has no
/// markdown spelling and so cannot survive a save: see `MarkdownStyling.normalize`, which is what
/// takes it back off.
///
/// The case order is the nesting order the writer uses. It only has to be *fixed*, so that
/// overlapping runs come out nested the same way every time.
enum Emphasis: CaseIterable {
    case strong
    case strikethrough
    case emphasis

    var delimiter: String {
        switch self {
        case .strong: MarkdownSyntax.strong
        case .strikethrough: MarkdownSyntax.strikethrough
        case .emphasis: MarkdownSyntax.emphasis
        }
    }

    /// Whether a run carrying `attributes` has this emphasis on it.
    ///
    /// Strikethrough is read as a *drawn* line rather than as a key that is present:
    /// `NSUnderlineStyle.none` is the raw value `0`, and a dropped or pasted run that spells "no
    /// strikethrough" explicitly would otherwise be given one by the next `normalize` — and
    /// `~~…~~` in the store by the save after that.
    func isOn(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
        switch self {
        case .strong: (attributes[.font] as? PlatformFont)?.isBold ?? false
        case .emphasis: (attributes[.font] as? PlatformFont)?.isItalic ?? false
        case .strikethrough: (attributes[.strikethroughStyle] as? Int).map { $0 != 0 } ?? false
        }
    }
}
