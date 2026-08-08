import AppKit

extension NSPasteboard {
    /// The clipboard as markdown: what ⌘V inserts.
    ///
    /// Rich flavors first here, unlike `plainTextForPaste` — the point of this reading is to
    /// keep the source app's bold, italic, strikethrough and links, which only the markup
    /// carries. Everything the app has no markdown for (colour, alignment, size, tables) is
    /// dropped rather than smuggled into the note as attributes nothing can remove (#117).
    ///
    /// nil means the clipboard holds no text at all — an image, say — rather than empty text.
    func markdownForPaste() -> String? {
        let rich = readObjects(forClasses: [NSAttributedString.self]) as? [NSAttributedString] ?? []
        if let converted = Self.joined(rich.map { $0.markdownRepresentation() }) {
            return converted
        }

        return plainTextForPaste()
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
    private static func joined(_ texts: [String]) -> String? {
        let joined = texts.filter { !$0.isEmpty }.joined(separator: "\n")
        return joined.isEmpty ? nil : joined
    }
}

extension NSAttributedString {
    /// This string rewritten as markdown, in the vocabulary `MarkdownSyntax` can parse back.
    ///
    /// Run by run: each run's traits become delimiters around its characters. Only the four
    /// inline constructs are recognised, because those are the four the editor has commands for
    /// — the rule the whole markdown swap exists to hold is that nothing enters a note which no
    /// command can take back out.
    ///
    /// Two known lossy edges, both accepted rather than papered over:
    ///
    /// * Text that already contains `*`, `~` or `[` is not escaped, so it may come back styled.
    ///   `MarkdownSyntax` has no escapes to escape it *to*, and inventing them would put a
    ///   backslash grammar into a scratchpad to fix a rare cosmetic miss.
    /// * Lists arrive as their characters. A pasted HTML `<ul>` keeps its bullets only if the
    ///   source app wrote them into the text.
    func markdownRepresentation() -> String {
        var markdown = ""
        var pending: Run?

        let whole = NSRange(location: 0, length: length)
        enumerateAttributes(in: whole, options: []) { attributes, range, _ in
            let text = attributedSubstring(from: range).string
            guard !text.isEmpty else { return }

            // A link's label carries the run's traits too, but the parser does not read the
            // inside of a label, so the link wins and the traits are dropped.
            let link = Self.url(in: attributes)
            let delimiters = link == nil ? Self.delimiters(for: attributes) : []

            // Runs are split by *any* attribute change, including ones with no markdown at all.
            // A bold phrase with one word in a different colour arrives as three runs, and
            // emitting each separately would give `**bold **` + `**red**` + `**  rest**` rather
            // than one pair around the phrase. Anything that spells the same markdown is joined
            // back together first.
            if var current = pending, current.delimiters == delimiters, current.link == link {
                current.text += text
                pending = current
            } else {
                if let current = pending { markdown += current.markdown }
                pending = Run(delimiters: delimiters, link: link, text: text)
            }
        }

        if let current = pending { markdown += current.markdown }
        return markdown
    }

    /// One stretch of text that spells a single piece of markdown.
    private struct Run {
        var delimiters: [String]
        var link: String?
        var text: String

        var markdown: String {
            if let link { return "[\(text)](\(link))" }
            guard !delimiters.isEmpty else { return text }

            // A construct never spans lines, so each line is wrapped in its own pair.
            return text.split(separator: "\n", omittingEmptySubsequences: false)
                .map { wrapped(String($0)) }
                .joined(separator: "\n")
        }

        /// Wraps a line's content, leaving whatever whitespace surrounds it outside the
        /// delimiters. `MarkdownSyntax` will not close a delimiter against whitespace, so
        /// `**bold **` is not bold — it is four literal asterisks that no command can remove.
        private func wrapped(_ line: String) -> String {
            let core = line.trimmingCharacters(in: .whitespaces)
            guard !core.isEmpty, let range = line.range(of: core) else { return line }

            let wrapped = delimiters.reduce(core) { "\($1)\($0)\($1)" }
            return line[line.startIndex..<range.lowerBound] + wrapped + line[range.upperBound...]
        }
    }

    private static func delimiters(for attributes: [NSAttributedString.Key: Any]) -> [String] {
        var delimiters: [String] = []

        if let font = attributes[.font] as? NSFont {
            let traits = NSFontManager.shared.traits(of: font)
            if traits.contains(.boldFontMask) { delimiters.append(MarkdownSyntax.strong) }
            if traits.contains(.italicFontMask) { delimiters.append(MarkdownSyntax.emphasis) }
        }

        if let style = attributes[.strikethroughStyle] as? Int, style != 0 {
            delimiters.append(MarkdownSyntax.strikethrough)
        }

        return delimiters
    }

    private static func url(in attributes: [NSAttributedString.Key: Any]) -> String? {
        switch attributes[.link] {
        case let url as URL: url.absoluteString
        case let string as String: string
        default: nil
        }
    }
}
