import SwiftUI
import UIKit

struct IOSRichTextEditor: UIViewRepresentable {
    var notes: [NoteItem]
    @Binding var selectedNoteIndex: Int

    /// See the note in `MacRichTextEditor`: a reference, so the coordinator outliving this
    /// struct does not leave it writing to a stale one.
    let statistics: EditorStatistics

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        context.coordinator.setup(container: container, notes: notes, selectedIndex: selectedNoteIndex)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.update(notes: notes, selectedIndex: selectedNoteIndex)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(statistics: statistics)
    }

    class Coordinator: NoteEditorCoordinator, UITextViewDelegate {
        private let statistics: EditorStatistics

        /// Forwards the base class's two seams, so a test can hand this a scratch defaults suite
        /// and a private notification centre.
        init(
            statistics: EditorStatistics,
            defaults: UserDefaults = .standard,
            notificationCenter: NotificationCenter = .default
        ) {
            self.statistics = statistics
            super.init(defaults: defaults, notificationCenter: notificationCenter)
        }

        override func makeEditorView() -> UIView {
            let textView = MarkdownTextView()

            textView.delegate = self

            // The view paints its own styling from its own text, on the one hook that knows
            // which characters changed. See `MarkdownTextView.textStorage(_:didProcessEditing:…)`.
            textView.textStorage.delegate = textView

            // The user cannot apply attributes; this view's attributes are derived from its own
            // text and repainted after every change. See `MarkdownStyling`.
            textView.allowsEditingTextAttributes = false
            textView.backgroundColor = .clear

            // Apply text padding
            textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

            return textView
        }

        override func load(_ text: String, into editorView: UIView) {
            (editorView as? MarkdownTextView)?.load(markdown: text)
        }

        /// Applies the note's mode and the app-wide zoom. A zoom step repaints; a mode step
        /// converts the buffer, because the two modes hold different things. See the macOS twin.
        override func configure(_ editorView: UIView, appearance: MarkdownStyling.Appearance) {
            (editorView as? MarkdownTextView)?.apply(appearance)
        }

        override func resignFocus(from editorView: UIView) {
            if editorView.isFirstResponder {
                editorView.resignFirstResponder()
            }
        }

        override func focus(_ editorView: UIView) {
            editorView.becomeFirstResponder()
        }

        override func plainText(of editorView: UIView) -> String {
            (editorView as? UITextView)?.text ?? ""
        }

        override func markdown(of editorView: UIView) -> String {
            (editorView as? MarkdownTextView)?.markdown ?? ""
        }

        override func statsDidChange(_ stats: TextStats) {
            statistics.stats = stats
        }

        /// Continues or ends a list when Return is pressed on one. See the macOS editor for
        /// why declining the newline here is safe against re-entry.
        func textView(
            _ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String
        ) -> Bool {
            guard text == "\n",
                let markdownView = textView as? MarkdownTextView,
                let edit = ListContinuation.returnEdit(
                    in: (textView.text ?? "") as NSString, selectedRange: range)
            else { return true }

            markdownView.applyMarkup(edit)
            return false
        }

        func textViewDidChange(_ textView: UITextView) {
            guard let textView = textView as? MarkdownTextView else { return }

            // The storage has already been normalized by now — the text view is its own storage
            // delegate. Only the typing attributes are left, which no storage pass can reach.
            textView.normalizeTypingAttributes()
            noteDidChange()
        }
    }
}

/// The editor's text view: a buffer whose shape is its note's mode.
///
/// See the macOS twin for the design. The two differ only where the frameworks do: `UITextView`
/// already gives each view its own undo manager, and there is no `writablePasteboardTypes` to
/// narrow, so `copy(_:)` writes the clipboard itself rather than filtering what AppKit would.
class MarkdownTextView: UITextView, NSTextStorageDelegate {
    /// How this view draws, and which of the two shapes its buffer is in. Display only — none of
    /// it is ever stored. `nil` until something configures it; see the macOS twin for why that
    /// is what makes the first `configure` do anything.
    private var configuredStyling: MarkdownStyling.Appearance?

    /// What the view draws as now: what it was last configured with, or what a bare text view is
    /// before anything has.
    var styling: MarkdownStyling.Appearance { configuredStyling ?? Self.unconfigured }

    private static let unconfigured = MarkdownStyling.Appearance(
        plainText: false, fontSize: AppConstants.Layout.defaultFontSize)

    /// The note as it would be stored: markdown, whichever mode this view is in.
    var markdown: String {
        styling.isStyled ? MarkdownWriting.markdown(from: textStorage) : (text ?? "")
    }

    /// The *selection* as the note would store it, on the same terms.
    ///
    /// Split out from `copy(_:)` because this is the half with a decision in it and
    /// `UIPasteboard.general` is the half a test cannot reach.
    var markdownForSelection: String {
        guard styling.isStyled else {
            return ((text ?? "") as NSString).substring(with: selectedRange)
        }
        return MarkdownWriting.markdown(from: textStorage.attributedSubstring(from: selectedRange))
    }

    /// The selection leaves on the clipboard as markdown source.
    ///
    /// In formatted mode the buffer holds no delimiters at all, so its characters alone would lose
    /// a copied note's formatting — a bold run pasted back as unformatted text.
    override func copy(_ sender: Any?) {
        write(markdownForSelection)
    }

    /// `super` deletes, registers the undo step and reports the change — only what it leaves on
    /// the clipboard is wrong, and assigning `string` replaces the whole item.
    override func cut(_ sender: Any?) {
        let markdown = markdownForSelection
        super.cut(sender)
        write(markdown)
    }

    private func write(_ markdown: String) {
        guard !markdown.isEmpty else { return }

        UIPasteboard.general.string = markdown
    }

    /// The clipboard read as the source `copy(_:)` writes it: what it describes, not its
    /// delimiters.
    ///
    /// The other half of the pair above, and it has to be here — a note copied out of this app and
    /// pasted back in would otherwise arrive as the six characters of `**bold**`, and the next save
    /// escapes them into the store. macOS reads the clipboard the same way, through
    /// `EditorShortcutManager.pasteAsMarkdown`.
    ///
    /// Plain mode takes the characters as they are, which is what that mode means. There is no ⌘⇧V
    /// on iOS to say so for a formatted note; switching the note to plain is how you paste literally.
    override func paste(_ sender: Any?) {
        guard styling.isStyled, let source = UIPasteboard.general.string, !source.isEmpty else {
            super.paste(sender)
            return
        }

        paste(markdown: source)
    }

    /// The half of the paste with a decision in it, split out for the reason `markdownForSelection`
    /// is: `UIPasteboard.general` is the half a test cannot reach.
    ///
    /// Inserted a run at a time through `insertText`, which is the path a keystroke takes — the view
    /// registers the undo step and reports the change to its delegate, neither of which an edit of
    /// the storage by hand would do. One undo group around the lot, so a paste comes back off in one
    /// press rather than one per run.
    func paste(markdown source: String) {
        let attributed = RichTextRendering.attributed(from: source, appearance: styling)
        let whole = NSRange(location: 0, length: attributed.length)
        guard whole.length > 0 else { return }

        let characters = attributed.string as NSString
        let typing = typingAttributes

        undoManager?.beginUndoGrouping()
        attributed.enumerateAttributes(in: whole, options: []) { attributes, run, _ in
            typingAttributes = attributes
            insertText(characters.substring(with: run))
        }
        undoManager?.setActionName("Paste")  // while the group is open: it names that group
        undoManager?.endUndoGrouping()

        // The caret continues in what it was in before the paste, not in the last run of it: a
        // pasted bold ending at the caret would otherwise make everything typed after it bold.
        typingAttributes = MarkdownStyling.normalized(typing, in: styling)
    }

    /// Puts a note's markdown into the view, in the shape its mode calls for.
    ///
    /// The selection is put back as a caret at its head: after a mode switch, the run it covered is
    /// not the run at those offsets any more. `setAttributedString` preserves the selection itself
    /// and clamps a location past the new end, so the `min` is belt and braces.
    func load(markdown: String) {
        let caret = selectedRange

        undoManager?.removeAllActions()  // its ranges describe a buffer that is being replaced
        textStorage.setAttributedString(
            RichTextRendering.attributed(from: markdown, appearance: styling))
        undoManager?.removeAllActions()

        selectedRange = NSRange(location: min(caret.location, textStorage.length), length: 0)
        typingAttributes = MarkdownStyling.baseAttributes(styling)
    }

    /// Applies a mode and a zoom level. See the macOS twin for why a mode step is a conversion.
    func apply(_ appearance: MarkdownStyling.Appearance) {
        guard appearance != configuredStyling else { return }

        // Read before the new appearance is recorded, and only for a mode step: writing the buffer
        // out renders every line through the spelling ladder, which is more work than the repaint
        // a zoom step asks for.
        let source = appearance.plainText != styling.plainText ? markdown : nil
        configuredStyling = appearance

        if let source {
            load(markdown: source)
        } else {
            MarkdownStyling.normalize(styling, in: textStorage)
            typingAttributes = MarkdownStyling.normalized(typingAttributes, in: styling)
        }
    }

    /// Takes an edit back to what this app can express. See the macOS twin.
    ///
    /// `NSTextStorage.EditActions` here where AppKit spells the same type
    /// `NSTextStorageEditActions` — the one place the two editors cannot share a signature.
    func textStorage(
        _ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorage.EditActions,
        range editedRange: NSRange, changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }

        MarkdownStyling.normalize(styling, in: textStorage, over: editedRange)
    }

    /// Typing attributes are not part of the storage, so no pass over it can cover them — they
    /// are the half of #117 that undo does not restore.
    func normalizeTypingAttributes() {
        typingAttributes = MarkdownStyling.normalized(typingAttributes, in: styling)
    }

    /// Applies an edit whose replacement is markup this app wrote — a list marker, a checkbox —
    /// in the note's own body face rather than in whatever run it lands in.
    ///
    /// `caretFollowsMarkup` defaults to true for the list continuation, which is where the caret
    /// ends up. See `TextEdit` for what it costs to get it wrong.
    func applyMarkup(_ edit: TextEdit, caretFollowsMarkup: Bool = true) {
        apply(
            edit, attributes: MarkdownStyling.baseAttributes(styling),
            caretFollowsMarkup: caretFollowsMarkup)
    }
}
