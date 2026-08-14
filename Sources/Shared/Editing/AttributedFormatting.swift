import Foundation

#if canImport(UIKit)
    import UIKit
#else
    import AppKit
#endif

/// What `⌘B`, `⌘I` and `⌘⇧X` do in formatted mode: turn a trait on over the selection, or off
/// again.
///
/// This is the whole reason formatted mode holds rich text rather than markdown source. A trait
/// is set membership — a run is bold or it is not — so the commands compose in any order and each
/// one is always its own inverse. Under delimiters they were neither: bold, then italic, then
/// bold again produced `**_**hello**_**`, because `⌘B` could only recognise a `**` pair sitting
/// immediately beside the selection and the italic pair had moved it out of reach (#124).
///
/// One rule survives from the delimiter days: the word boundary. `_` is a word character in
/// every identifier a scratchpad holds, so italic mid-word is declined rather than applied — it
/// is the one trait `MarkdownWriting` cannot spell there, and a command that leaves the buffer in
/// a state the writer has to drop is a command that loses work.
enum AttributedFormatting {
    /// Whether every character in `range` that could carry `emphasis` already does.
    ///
    /// Line terminators are not asked, because no answer they give is meaningful: a construct
    /// never spans lines, so the writer refuses a trait on a terminator and every note that has
    /// been through one save comes back with bare newlines between its runs. Counting them made
    /// the first ⌘B on a paragraph that was already bold when the note opened *re-apply* the
    /// bold — nothing visibly happened, and the user had to press twice.
    ///
    /// False for a range with nothing spellable in it, which never matters: an empty selection
    /// reads the typing attributes instead, and an empty note has nothing to toggle.
    static func isApplied(
        _ emphasis: Emphasis, over range: NSRange,
        in storage: NSAttributedString
    ) -> Bool {
        guard range.length > 0 else { return false }
        let text = storage.string as NSString

        var asked = false
        var applied = true
        storage.enumerateAttributes(in: range, options: []) { attributes, subrange, stop in
            guard isSpellable(subrange, in: text) else { return }
            asked = true

            guard emphasis.isOn(attributes) else {
                applied = false
                stop.pointee = true
                return
            }
        }

        return asked && applied
    }

    /// Whether `range` holds anything but line terminators.
    private static func isSpellable(_ range: NSRange, in text: NSString) -> Bool {
        (range.location..<NSMaxRange(range)).contains {
            !MarkdownSyntax.isNewline(text.character(at: $0))
        }
    }

    /// Toggles `emphasis` over `range`, and answers with what typing should continue in.
    ///
    /// The direction is decided once for the whole selection — off only when every character
    /// already carries it — so a partly-bold selection goes fully bold on the first press and
    /// fully plain on the second, rather than inverting run by run.
    @discardableResult
    static func toggle(
        _ emphasis: Emphasis, over range: NSRange,
        in storage: NSMutableAttributedString, appearance: MarkdownStyling.Appearance
    ) -> [NSAttributedString.Key: Any] {
        let core = trimmed(range, in: storage.string as NSString)
        let applying = !isApplied(emphasis, over: core, in: storage)

        guard core.length > 0 else {
            return typingAttributes(
                emphasis, applying: applying, at: range.location, in: storage,
                appearance: appearance)
        }

        guard applying == false || canApply(emphasis, over: core, in: storage) else {
            return storage.attributes(at: min(core.location, storage.length - 1), effectiveRange: nil)
        }

        set(emphasis, applying, over: core, in: storage, appearance: appearance)
        return storage.attributes(at: core.location, effectiveRange: nil)
    }

    /// Applies or removes the trait, run by run, keeping everything else each run carries.
    private static func set(
        _ emphasis: Emphasis, _ applying: Bool, over range: NSRange,
        in storage: NSMutableAttributedString, appearance: MarkdownStyling.Appearance
    ) {
        var updates: [(NSRange, [NSAttributedString.Key: Any])] = []

        storage.enumerateAttributes(in: range, options: []) { attributes, subrange, _ in
            updates.append(
                (subrange, applied(emphasis, applying, to: attributes, appearance: appearance)))
        }

        for (subrange, attributes) in updates {
            storage.setAttributes(attributes, range: subrange)
        }
    }

    /// One run's attributes with the trait added or taken away.
    ///
    /// Removing a font trait means rebuilding the font from the base one and putting back the
    /// *other* trait, because a symbolic trait cannot be subtracted from a font that has it.
    ///
    /// The colour is re-derived rather than carried over, so `⌘B` puts the note's tint on and
    /// takes it off. Nothing else would: this writes attributes, not characters, so the storage
    /// delegate that normalizes every other edit never sees it.
    private static func applied(
        _ emphasis: Emphasis, _ applying: Bool,
        to attributes: [NSAttributedString.Key: Any], appearance: MarkdownStyling.Appearance
    ) -> [NSAttributedString.Key: Any] {
        var updated = attributes
        let font = (attributes[.font] as? PlatformFont) ?? appearance.baseFont

        switch emphasis {
        case .strikethrough:
            updated[.strikethroughStyle] = applying ? NSUnderlineStyle.single.rawValue : nil
        case .strong:
            updated[.font] = rebuilt(font, bold: applying, italic: font.isItalic, appearance)
        case .emphasis:
            updated[.font] = rebuilt(font, bold: font.isBold, italic: applying, appearance)
        }

        updated[.foregroundColor] = MarkdownStyling.foregroundColor(for: updated, in: appearance)
        return updated
    }

    private static func rebuilt(
        _ font: PlatformFont, bold: Bool, italic: Bool, _ appearance: MarkdownStyling.Appearance
    ) -> PlatformFont {
        var rebuilt = appearance.baseFont
        if bold { rebuilt = rebuilt.bolded() }
        if italic { rebuilt = rebuilt.italicized() }
        return rebuilt
    }

    /// What the caret should type in when the command was pressed with nothing selected.
    ///
    /// `⌘B` then typing is bold, the way it is in every other editor. Nothing is written to the
    /// buffer, so nothing is left behind if the user presses it and types nothing.
    private static func typingAttributes(
        _ emphasis: Emphasis, applying: Bool, at caret: Int,
        in storage: NSAttributedString, appearance: MarkdownStyling.Appearance
    ) -> [NSAttributedString.Key: Any] {
        let current =
            storage.length > 0
            ? storage.attributes(at: min(caret, storage.length - 1), effectiveRange: nil)
            : MarkdownStyling.baseAttributes(appearance)

        return applied(
            emphasis, !emphasis.isOn(current), to: current, appearance: appearance)
    }

    // MARK: - Reading

    /// Whether the trait can be written back out at this position. Only `_` can fail, and only
    /// against a word character: `key_x_store` is a name, not italic text.
    private static func canApply(
        _ emphasis: Emphasis, over range: NSRange, in storage: NSAttributedString
    ) -> Bool {
        guard MarkdownSyntax.mindsWordBoundaries(emphasis.delimiter) else { return true }
        let text = storage.string as NSString

        let before = range.location - 1
        if before >= 0, MarkdownSyntax.isWordCharacter(text.character(at: before)) { return false }

        let after = NSMaxRange(range)
        if after < text.length, MarkdownSyntax.isWordCharacter(text.character(at: after)) {
            return false
        }

        return true
    }

    /// `range` with leading and trailing whitespace dropped, so a selection with a trailing space
    /// formats the word and not the space — the writer would put the space outside the pair
    /// anyway, and a trait that vanishes on save is worse than one that never went on.
    private static func trimmed(_ range: NSRange, in text: NSString) -> NSRange {
        var start = range.location
        var end = min(NSMaxRange(range), text.length)

        while start < end, MarkdownSyntax.isWhitespace(text.character(at: start)) { start += 1 }
        while end > start, MarkdownSyntax.isWhitespace(text.character(at: end - 1)) { end -= 1 }

        return NSRange(location: start, length: end - start)
    }
}
