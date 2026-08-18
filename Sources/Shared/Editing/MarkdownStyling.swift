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

/// How a note's text is drawn, and what an editor is allowed to hold.
///
/// The two modes are opposites, and the split is the point (#124):
///
/// * **Formatted** holds rich text with no markdown in it at all. `**keys**` was parsed into a
///   bold run on the way in and is written back out on the way to the store — see
///   `RichTextRendering` and `MarkdownWriting`. `⌘B` toggles a trait, so it is order-free and
///   its own inverse; deleting text deletes text. Nothing is on screen the user did not type.
/// * **Plain** holds the source verbatim, every delimiter visible, in one monospaced font.
///
/// Whichever mode a note is in, **nothing here is ever stored**: `NoteItem` holds a markdown
/// `String`, and the attributes below are rebuilt from it on the way in. That is the fix for
/// #117, and it survives the move to rich text — a paste can still arrive carrying colour,
/// alignment and a 24pt font, and `normalize` takes the whole lot back off. What is left is the
/// vocabulary the commands can reach, which is the only thing `MarkdownWriting` can spell.
enum MarkdownStyling {
    /// What decides how a note looks: its mode, the app-wide zoom, and — on iOS — the system text
    /// size the zoom is scaled by, which arrives through `baseFont` rather than as a field.
    struct Appearance: Equatable {
        /// Monospaced, and every character of the markdown left exactly as typed — for
        /// credentials and keys, where a proportional font gets in the way, and for reading the
        /// source of what the other mode draws.
        let plainText: Bool

        /// Passed in rather than read from `EditorFontSize.current()` here. Defaulting it made
        /// every appearance read `UserDefaults.standard` no matter which suite the caller was
        /// given, so a test that stepped the zoom in a scratch suite checked a number that never
        /// reached a repaint.
        let fontSize: CGFloat

        /// The colour bold runs are drawn in, and only in formatted mode — plain mode is one
        /// font in one colour by definition. `nil` leaves bold in the body-text colour, which is
        /// what a caller with no note in hand gets: `MarkdownWriting` reads traits, never draws.
        let tintedNoteIndex: Int?

        /// The font every attribute in the note is derived from, resolved on init so that the
        /// *drawn* size is part of this type's identity.
        ///
        /// `fontSize` is not the size on screen: on iOS `editorBody` scales it by Settings › Text
        /// Size, and none of the fields above move when that setting does. Appearances built either
        /// side of the change compared equal, so both editors' `apply` guard swallowed the repaint.
        let baseFont: PlatformFont

        init(plainText: Bool, fontSize: CGFloat, tintedNoteIndex: Int? = nil) {
            self.plainText = plainText
            self.fontSize = fontSize
            self.tintedNoteIndex = tintedNoteIndex
            self.baseFont = .editorBody(plainText: plainText, size: fontSize)
        }

        /// Whether this mode draws formatting rather than the characters that describe it.
        var isStyled: Bool { !plainText }
    }

    /// What every character starts as, and what typing continues in.
    static func baseAttributes(_ appearance: Appearance) -> [NSAttributedString.Key: Any] {
        [
            .font: appearance.baseFont,
            .foregroundColor: PlatformColor.adaptiveEditorText
        ]
    }

    /// Brings `storage` back to what this app can express, and to the current zoom.
    ///
    /// Plain mode is flat by definition, so everything goes. Formatted mode keeps the four things
    /// with a markdown spelling — bold, italic, strikethrough, links — and takes the rest: any
    /// other colour, any other font, alignment, kerning, the lot. A pasted 24pt centred red run
    /// therefore lands as ordinary text in the note's own font, still bold if it was bold.
    static func normalize(_ appearance: Appearance, in storage: NSMutableAttributedString) {
        let whole = NSRange(location: 0, length: storage.length)
        guard whole.length > 0 else { return }

        storage.beginEditing()
        normalize(appearance, in: storage, over: whole)
        storage.endEditing()
    }

    /// The same, over the range an edit landed on.
    ///
    /// No `beginEditing`/`endEditing` here: the caller may already be inside `processEditing`,
    /// where opening another editing group is not allowed. The whole-buffer entry point above
    /// wraps its own.
    static func normalize(
        _ appearance: Appearance, in storage: NSMutableAttributedString, over range: NSRange
    ) {
        let clamped = clamp(range, to: storage.length)
        guard clamped.length > 0 else { return }

        guard appearance.isStyled else {
            storage.setAttributes(baseAttributes(appearance), range: clamped)
            return
        }

        // Collected before anything is written: mutating attributes while enumerating the same
        // range is not defined behaviour.
        var replacements: [(NSRange, [NSAttributedString.Key: Any])] = []

        storage.enumerateAttributes(in: clamped, options: []) { attributes, subrange, _ in
            replacements.append((subrange, normalized(attributes, in: appearance)))
        }

        for (subrange, attributes) in replacements {
            storage.setAttributes(attributes, range: subrange)
        }
    }

    /// One run's attributes, reduced to the vocabulary and re-based on the note's own font.
    ///
    /// The traits are read off whatever font arrived and re-applied to the base one, so a pasted
    /// bold Helvetica 24 comes out bold in the editor's font at the editor's size. That is also
    /// what makes a zoom step work: every run is rebuilt at the new size, weight and slant intact.
    ///
    /// Not private: `typingAttributes` are not part of any storage, so the text views run the
    /// same filter over them by hand.
    static func normalized(
        _ attributes: [NSAttributedString.Key: Any], in appearance: Appearance
    ) -> [NSAttributedString.Key: Any] {
        guard appearance.isStyled else { return baseAttributes(appearance) }

        let existing = attributes[.font] as? PlatformFont
        let isBold = existing?.isBold == true

        var font = appearance.baseFont
        if isBold { font = font.bolded() }
        if existing?.isItalic == true { font = font.italicized() }

        var kept: [NSAttributedString.Key: Any] = [.font: font]

        if let link = attributes[.link] {
            kept[.link] = link
            kept[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }

        kept[.foregroundColor] = foregroundColor(
            isLink: attributes[.link] != nil, isBold: isBold, in: appearance)

        // Through `Emphasis`, which is the one place that decides what a trait being "on" means:
        // asking the dictionary here was a second answer, and it read `NSUnderlineStyle.none` as a
        // strikethrough.
        if Emphasis.strikethrough.isOn(attributes) {
            kept[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }

        return kept
    }

    /// What a run is drawn in.
    ///
    /// A link wins over bold: its colour is the one that already carried meaning, and a bold link
    /// that stopped looking like a link would trade one signal for another. Bold takes the note's
    /// tint, which is the delimiter formatted mode no longer has.
    ///
    /// Told what the run is rather than handed the run: digging the traits back out of a dictionary
    /// costs an `NSFontDescriptor` per run, and reading them from the dictionary being built made
    /// the call site's position silently load-bearing.
    private static func foregroundColor(
        isLink: Bool, isBold: Bool, in appearance: Appearance
    ) -> PlatformColor {
        if isLink { return .editorLink }

        guard isBold, let index = appearance.tintedNoteIndex else { return .adaptiveEditorText }

        return NotePalette.boldTint(forNoteIndex: index)
    }

    /// Paints the note's tint onto its bold runs, and nothing else.
    ///
    /// What `RichTextRendering` needs after its span loop, in place of a whole-buffer `normalize`
    /// whose only net effect was this colour: that loop starts from `baseAttributes` and writes
    /// nothing outside the vocabulary, so every font it rebuilt was identical to the one there.
    ///
    /// This runs after every span and skips runs carrying a link, so the link colour wins whichever
    /// order the parser emitted the two in.
    static func tintBold(_ appearance: Appearance, in storage: NSMutableAttributedString) {
        guard appearance.isStyled, let index = appearance.tintedNoteIndex else { return }

        let tint = NotePalette.boldTint(forNoteIndex: index)
        let whole = NSRange(location: 0, length: storage.length)

        // Collected before anything is written, for the reason `normalize` gives: writing an
        // attribute splits the runs being enumerated.
        var tinted: [NSRange] = []
        storage.enumerateAttributes(in: whole, options: []) { attributes, subrange, _ in
            guard attributes[.link] == nil,
                (attributes[.font] as? PlatformFont)?.isBold == true
            else { return }

            tinted.append(subrange)
        }

        for subrange in tinted {
            storage.addAttribute(.foregroundColor, value: tint, range: subrange)
        }
    }

    /// A range brought inside `length`.
    ///
    /// The edited range handed to a storage delegate describes text that may no longer be there:
    /// after a deletion it can start at or past the end of what is left. This is what stands
    /// between that and an out-of-range crash while typing.
    private static func clamp(_ range: NSRange, to length: Int) -> NSRange {
        let start = min(max(range.location, 0), length)
        return NSRange(location: start, length: min(range.length, length - start))
    }

    /// Rewrites the font of every run in `range` through `transform`.
    ///
    /// Reading each run's *current* font rather than starting again from `baseFont` is what lets
    /// constructs nest: the italic pass inside `**_keys_**` sees the bold face the strong pass
    /// left behind and adds to it, where assigning `baseFont.italicized()` would drop the weight.
    /// The runs are collected before any of them is changed, because mutating an attribute while
    /// enumerating that same attribute is not defined behaviour.
    static func restyle(
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
    /// The font every note is drawn in, and the one every other cut is derived from — so the single
    /// place text size is decided, on either platform.
    ///
    /// On iOS `size` is a *base* that Dynamic Type scales, not the final point size: a fixed
    /// `.systemFont(ofSize:)` overrides the system text size the user has already set, with nothing
    /// in the app to change it back. At the default content size category the metrics are the
    /// identity, so nothing moves for anyone who has not changed the setting.
    ///
    /// macOS has no such system setting, which is why `⌘+`/`⌘-` and `EditorFontSize` exist there
    /// and why this stays an exact point size on that platform.
    static func editorBody(plainText: Bool, size: CGFloat) -> PlatformFont {
        let base: PlatformFont =
            plainText
            ? .monospacedSystemFont(ofSize: size, weight: .regular)
            : .systemFont(ofSize: size)

        #if canImport(UIKit)
            // `.body` for both modes, or the two modes would disagree about how big the note is.
            //
            // `compatibleWith:` rather than the bare `scaledFont(for:)`, which reads `UIScreen`'s
            // own category and ignores the trait collection it is called under — untestable, and
            // wrong for a view whose environment differs from the screen's.
            return UIFontMetrics(forTextStyle: .body).scaledFont(for: base, compatibleWith: .current)
        #else
            return base
        #endif
    }

    /// The bold and italic cuts of this font, or this font unchanged when it has none.
    ///
    /// Falling back to the original rather than to a synthesised face keeps a bold run legible in
    /// a font that has no bold cut at all.
    #if canImport(UIKit)
        var isBold: Bool { fontDescriptor.symbolicTraits.contains(.traitBold) }
        var isItalic: Bool { fontDescriptor.symbolicTraits.contains(.traitItalic) }

        func bolded() -> PlatformFont { withTrait(.traitBold) }
        func italicized() -> PlatformFont { withTrait(.traitItalic) }

        private func withTrait(_ trait: UIFontDescriptor.SymbolicTraits) -> PlatformFont {
            guard let descriptor = fontDescriptor.withSymbolicTraits(
                fontDescriptor.symbolicTraits.union(trait))
            else { return self }
            return UIFont(descriptor: descriptor, size: pointSize)
        }
    #else
        var isBold: Bool { fontDescriptor.symbolicTraits.contains(.bold) }
        var isItalic: Bool { fontDescriptor.symbolicTraits.contains(.italic) }

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
    /// Applied on every normalize, which is what keeps it adaptive. Under RTF storage it had to
    /// be filled in on load instead — text layout falls back to opaque black for runs with no
    /// `.foregroundColor`, and RTF stores no colour for such runs, so notes went unreadable in
    /// dark mode. Nothing is stored now, so there is nothing to fill in.
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

    /// This colour flattened against one appearance, in sRGB — nil when the conversion fails.
    ///
    /// Both steps and in this order on macOS: `getHue` and `getRed` trap on a colour that is not
    /// already in an RGB space, and a dynamic `NSColor` is in none until it is resolved inside an
    /// explicit appearance. Shared so the platform fork is spelled once.
    func resolved(dark: Bool) -> PlatformColor? {
        #if canImport(UIKit)
            return resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light))
        #else
            var flattened: PlatformColor?
            NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
                flattened = self.usingColorSpace(.sRGB)
            }
            return flattened
        #endif
    }
}
