import CoreGraphics
import Foundation

#if canImport(UIKit)
    import UIKit

    typealias PlatformFont = UIFont
    typealias PlatformColor = UIColor
#else
    import AppKit

    typealias PlatformFont = NSFont
    typealias PlatformColor = NSColor
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
    struct Appearance {
        /// Monospaced, and markdown left as literal text — for credentials and keys, where a
        /// proportional font gets in the way and dimmed markers are just noise.
        let plainText: Bool

        /// Passed in rather than read from `EditorFontSize.current()` here. Defaulting it made
        /// every appearance read `UserDefaults.standard` no matter which suite the caller was
        /// given, so a test that stepped the zoom in a scratch suite checked a number that never
        /// reached a repaint.
        let fontSize: CGFloat

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
        apply(appearance, to: storage, over: whole)
        storage.endEditing()
    }

    /// Repaints just the lines `range` touches.
    ///
    /// What a line looks like depends on that line alone — constructs never span lines — so an
    /// edit only ever invalidates the lines it landed on. Repainting the whole note on every
    /// keystroke was correct but put O(document) attribute setting and a full layout
    /// invalidation on the main actor for each character typed.
    ///
    /// No `beginEditing`/`endEditing` here: the caller may already be inside `processEditing`,
    /// where opening another editing group is not allowed. The whole-document entry point above
    /// wraps its own.
    static func apply(
        _ appearance: Appearance, to storage: NSMutableAttributedString, over range: NSRange
    ) {
        let text = storage.string as NSString
        guard text.length > 0 else { return }

        let start = min(range.location, text.length)
        let clamped = NSRange(location: start, length: min(range.length, text.length - start))
        let lines = text.lineRange(for: clamped)
        guard lines.length > 0 else { return }

        storage.setAttributes(baseAttributes(appearance), range: lines)
        guard appearance.isStyled else { return }

        for span in MarkdownSyntax.spans(in: text, over: lines) {
            apply(span, to: storage, appearance: appearance)
        }
    }

    private static func apply(
        _ span: MarkdownSyntax.Span, to storage: NSMutableAttributedString, appearance: Appearance
    ) {
        switch span.style {
        case .strong:
            restyle(storage, over: span.range) { $0.bolded() }
        case .emphasis:
            restyle(storage, over: span.range) { $0.italicized() }
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

    /// Rewrites the font of every run in `range` through `transform`.
    ///
    /// Reading each run's *current* font rather than starting again from `baseFont` is what lets
    /// constructs nest: the italic pass inside `**_keys_**` sees the bold face the strong pass
    /// left behind and adds to it, where assigning `baseFont.italicized()` would drop the weight.
    /// The runs are collected before any of them is changed, because mutating an attribute while
    /// enumerating that same attribute is not defined behaviour.
    private static func restyle(
        _ storage: NSMutableAttributedString, over range: NSRange,
        _ transform: (PlatformFont) -> PlatformFont
    ) {
        var updates: [(NSRange, PlatformFont)] = []

        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            guard let font = value as? PlatformFont else { return }
            updates.append((subrange, transform(font)))
        }

        for (subrange, font) in updates {
            storage.addAttribute(.font, value: font, range: subrange)
        }
    }
}

extension PlatformFont {
    static func editorBody(plainText: Bool, size: CGFloat) -> PlatformFont {
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
    /// The system's body-text colour: black in light appearance, white in dark.
    ///
    /// Applied to the whole note on every repaint, which is what keeps it adaptive. Under RTF
    /// storage it had to be filled in on load instead — text layout falls back to opaque black
    /// for runs with no `.foregroundColor`, and RTF stores no colour for such runs, so notes
    /// went unreadable in dark mode. Nothing is stored now, so there is nothing to fill in.
    static var adaptiveEditorText: PlatformColor {
        #if canImport(UIKit)
            .label
        #else
            .textColor
        #endif
    }

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
