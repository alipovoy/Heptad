import CoreGraphics
import Foundation

#if canImport(UIKit)
    import UIKit

    typealias PlatformFont = UIFont
#else
    import AppKit

    typealias PlatformFont = NSFont
#endif

/// How a note's markdown is drawn.
///
/// Every attribute this file produces is **derived state**: it is recomputed from the text after
/// each change and never saved — `NoteItem` stores a `String`. That is the whole fix for #117.
/// Undo restores text storage but not `typingAttributes`, so under attributed storage a paste
/// could strand colour and alignment the app had no command to remove. Here there is nothing to
/// strand: the next repaint overwrites every attribute in the view, and none of them were ever
/// going to be written to disk anyway.
///
/// It is also what makes the plain-text toggle non-destructive. Plain mode is a different
/// `Appearance`, not a different document.
enum MarkdownStyling {
    /// The two things that decide how a note looks: its mode, and the app-wide zoom.
    struct Appearance: Equatable {
        /// Monospaced, and markdown left as literal text — for credentials and keys, where a
        /// proportional font gets in the way and dimmed markers are just noise.
        let plainText: Bool
        let fontSize: CGFloat

        init(plainText: Bool, fontSize: CGFloat = EditorFontSize.current()) {
            self.plainText = plainText
            self.fontSize = fontSize
        }

        var baseFont: PlatformFont { .editorBody(plainText: plainText, size: fontSize) }

        /// Plain mode shows the source and nothing else, so there is no styling pass at all.
        var isStyled: Bool { !plainText }
    }

    /// What every character starts as, and what typing continues in.
    static func baseAttributes(_ appearance: Appearance) -> [NSAttributedString.Key: Any] {
        [
            .font: appearance.baseFont,
            .foregroundColor: PlatformColor.adaptiveEditorText
        ]
    }

    /// Repaints `storage` from its own text.
    ///
    /// Unconditionally clears to the base attributes first. That single line is what makes a
    /// paste harmless: whatever colour, alignment or font arrived with it is gone by the end of
    /// this call, and only the characters are left.
    static func apply(_ appearance: Appearance, to storage: NSMutableAttributedString) {
        let whole = NSRange(location: 0, length: storage.length)
        guard whole.length > 0 else { return }

        storage.beginEditing()
        storage.setAttributes(baseAttributes(appearance), range: whole)

        if appearance.isStyled {
            for span in MarkdownSyntax.spans(in: storage.string as NSString) {
                apply(span, to: storage, appearance: appearance)
            }
        }

        storage.endEditing()
    }

    private static func apply(
        _ span: MarkdownSyntax.Span, to storage: NSMutableAttributedString, appearance: Appearance
    ) {
        switch span.style {
        case .strong:
            storage.addAttribute(.font, value: appearance.baseFont.bolded(), range: span.range)
        case .emphasis:
            storage.addAttribute(.font, value: appearance.baseFont.italicized(), range: span.range)
        case .strikethrough:
            storage.addAttribute(
                .strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: span.range)
        case .link:
            storage.addAttribute(.foregroundColor, value: PlatformColor.editorLink, range: span.range)
            storage.addAttribute(
                .underlineStyle, value: NSUnderlineStyle.single.rawValue, range: span.range)
        case .marker:
            // Dimmed rather than hidden: the buffer holds the source, so the caret has to be
            // able to sit inside `**` and arrow through it. Hiding the markers would leave the
            // selection jumping over characters that are still there.
            storage.addAttribute(
                .foregroundColor, value: PlatformColor.editorMarker, range: span.range)
        }
    }
}

extension PlatformFont {
    static func editorBody(plainText: Bool, size: CGFloat = AppConstants.Layout.defaultFontSize)
        -> PlatformFont
    {
        plainText
            ? .monospacedSystemFont(ofSize: size, weight: .regular)
            : .systemFont(ofSize: size)
    }

    /// The bold and italic cuts of this font, or this font unchanged when it has none.
    ///
    /// Falling back to the original rather than to a synthesised face keeps `**text**` legible
    /// in a plain-text note's monospaced font, which on some systems has no italic at all.
    #if canImport(UIKit)
        func bolded() -> PlatformFont { withTrait(.traitBold) }
        func italicized() -> PlatformFont { withTrait(.traitItalic) }

        private func withTrait(_ trait: UIFontDescriptor.SymbolicTraits) -> PlatformFont {
            guard let descriptor = fontDescriptor.withSymbolicTraits(
                fontDescriptor.symbolicTraits.union(trait))
            else { return self }
            return UIFont(descriptor: descriptor, size: pointSize)
        }
    #else
        func bolded() -> PlatformFont { withTrait(.bold) }
        func italicized() -> PlatformFont { withTrait(.italic) }

        private func withTrait(_ trait: NSFontDescriptor.SymbolicTraits) -> PlatformFont {
            let descriptor = fontDescriptor.withSymbolicTraits(
                fontDescriptor.symbolicTraits.union(trait))
            return NSFont(descriptor: descriptor, size: pointSize) ?? self
        }
    #endif
}

extension PlatformColor {
    /// A link's label. The system's own link colour, so it tracks the accent.
    static var editorLink: PlatformColor {
        #if canImport(UIKit)
            .link
        #else
            .linkColor
        #endif
    }

    /// The syntax characters themselves, pushed back so they read as punctuation.
    static var editorMarker: PlatformColor {
        #if canImport(UIKit)
            .tertiaryLabel
        #else
            .tertiaryLabelColor
        #endif
    }
}
