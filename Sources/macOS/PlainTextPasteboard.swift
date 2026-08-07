import AppKit

extension NSPasteboard {
    /// The clipboard as plain text, whichever flavor it arrived in.
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
