import AppKit

extension NSPasteboard.PasteboardType {
    /// A note's own markdown, under a type only this app writes.
    ///
    /// What keeps a copy from one note into another exact now that ⌘C also offers RTF: ⌘V prefers
    /// rich flavors, so without this an in-app paste would go out through `RichTextExport` and
    /// back through `MarkdownWriting` — two conversions that are inverse, where reading this one
    /// is no conversion at all.
    static let heptadMarkdown = NSPasteboard.PasteboardType("dev.lipovoy.heptad.markdown")
}

extension NSPasteboard {
    /// The clipboard as markdown: what ⌘V inserts.
    ///
    /// Rich flavors first here, unlike `plainTextForPaste` — the point of this reading is to
    /// keep the source app's bold, italic, strikethrough and links, which only the markup
    /// carries. Everything the app has no markdown for (colour, alignment, size, tables) is
    /// dropped rather than smuggled into the note as attributes nothing can remove (#117).
    ///
    /// nil means the clipboard holds no text at all — an image, say — rather than empty text.
    /// Only a clipboard that actually carries formatting is rewritten. Bare characters are
    /// already text — markdown someone wrote by hand, or a note copied out of this app — and
    /// putting them through the writer would escape the delimiters they meant. ⌘⇧V is the
    /// shortcut for reading them literally; ⌘V reads them as the source they look like.
    func markdownForPaste() -> String? {
        // This app's own copy, read before anything is decoded: it is already the markdown every
        // branch below is working towards, and taking it verbatim is what keeps ⌘C then ⌘V inside
        // the app exact rather than merely inverse. It also skips the size bound below, which an
        // in-app copy has no reason to be held to.
        if let own = string(forType: .heptadMarkdown), !own.isEmpty {
            return NoteCharacters.storable(own)
        }

        guard richFlavorsAreWorthDecoding else { return plainTextForPaste() }

        let rich = readObjects(forClasses: [NSAttributedString.self]) as? [NSAttributedString] ?? []

        if rich.contains(where: \.carriesFormatting),
            let converted = Self.joined(rich.map { $0.markdownRepresentation() }) {
            return converted
        }

        return plainTextForPaste()
    }

    /// The most markup ⌘V will decode before falling back to pasting the clipboard's characters.
    ///
    /// 128 KB, about two seconds on the curve measured below — a wait, not a hang. It was 1 MB,
    /// which on that same curve is well over ten seconds of a beachballed app with ⌘V still
    /// undelivered: a bound in name only. Anything larger pastes as its characters instead.
    static let richPasteByteLimit = 1 << 17

    /// Whether the clipboard's markup is small enough to be worth decoding, which is what stands
    /// between ⌘V and an unbounded main-thread stall.
    ///
    /// `markdownForPaste` runs inside the key-event monitor with the key-down still undelivered,
    /// and the decode is super-linear: 23 KB of HTML measured at 250 ms, 203 KB at 2.9 seconds.
    /// Bounding the input makes the worst case "the bold did not survive" rather than a hang — see
    /// the limit above for where that bound sits. Sizes are read rather than decoded —
    /// `data(forType:)` is a copy, not a parse.
    private var richFlavorsAreWorthDecoding: Bool {
        let types: [NSPasteboard.PasteboardType] = [.html, .rtfd, .rtf]
        let markup = (pasteboardItems ?? []).reduce(0) { total, item in
            total + (types.compactMap { item.data(forType: $0)?.count }.max() ?? 0)
        }

        return markup <= Self.richPasteByteLimit
    }

    /// The clipboard as plain text, whichever flavor it arrived in: what ⌘⇧V inserts.
    ///
    /// `NSTextView.pasteAsPlainText` reads `public.utf8-plain-text` and stops there. macOS
    /// synthesizes that flavor from RTF, but not from HTML, RTFD or a URL — so on a clipboard
    /// carrying only one of those, ⌘V pasted through `readablePasteboardTypes` while ⌘⇧V
    /// silently inserted nothing (#114). Every flavor that chain can read is covered below.
    ///
    /// The order is this method's own rather than that chain's, which tries rich text first:
    /// what the source app already calls text beats anything decoded back out of its markup.
    ///
    /// nil means the clipboard holds no text at all — an image, say — rather than empty text.
    func plainTextForPaste() -> String? {
        let strings = readObjects(forClasses: [NSString.self]) as? [NSString] ?? []
        if let literal = Self.joined(strings.map { $0 as String }) {
            return literal
        }

        // One read covers HTML, RTFD and RTF: each decodes to an attributed string, of which
        // only the characters are wanted here.
        let rich = readObjects(forClasses: [NSAttributedString.self]) as? [NSAttributedString] ?? []
        if let flattened = Self.joined(rich.map(\.string)) {
            return flattened
        }

        // A file URL pastes as its path, not its `file://` spelling — both what ⌘V does with the
        // same clipboard, and the one of the two worth having in a note.
        let urls = (readObjects(forClasses: [NSURL.self]) as? [NSURL] ?? []).map { $0 as URL }
        return Self.joined(urls.map { $0.isFileURL ? $0.path : $0.absoluteString })
    }

    /// Multiple items paste as multiple lines — the only reading of them that keeps every item.
    ///
    /// Empty ones are dropped rather than joined, which is what carries the flavor an app
    /// declared and left empty: it contributes nothing, so the search moves on to the next
    /// flavor instead of calling that clipboard successfully pasted.
    ///
    /// Every reading above ends here, so the characters a note may not hold are taken out here too:
    /// the `.string` flavor never goes near the writer, and ⌘⇧V inserts what this returns directly.
    private static func joined(_ texts: [String]) -> String? {
        let joined = texts.map(NoteCharacters.storable).filter { !$0.isEmpty }.joined(separator: "\n")
        return joined.isEmpty ? nil : joined
    }
}

extension NSAttributedString {
    /// This string rewritten as markdown, in the vocabulary `MarkdownSyntax` can parse back.
    ///
    /// The same writer the editor saves through, handed the clipboard instead of a note — which
    /// is what keeps a pasted bold run and a typed one spelling the same thing, and what gives
    /// the paste escaping for free: a code snippet holding `**` arrives as those two characters
    /// rather than as a bold run nobody asked for.
    ///
    /// Only the four inline constructs survive, because those are the four the editor has
    /// commands for — the rule the whole markdown swap exists to hold is that nothing enters a
    /// note which no command can take back out. Lists are the known lossy edge: they arrive as
    /// their characters, so a pasted HTML `<ul>` keeps its bullets only if the source app wrote
    /// them into the text.
    func markdownRepresentation() -> String {
        MarkdownWriting.markdown(from: self)
    }

    /// Whether anything in here has a markdown spelling at all. A clipboard with none is text
    /// rather than formatting, and is pasted as the characters it is.
    var carriesFormatting: Bool {
        var carries = false
        let whole = NSRange(location: 0, length: length)

        enumerateAttributes(in: whole, options: []) { attributes, _, stop in
            guard Emphasis.allCases.contains(where: { $0.isOn(attributes) })
                || attributes[.link] != nil
            else { return }

            carries = true
            stop.pointee = true
        }

        return carries
    }
}
