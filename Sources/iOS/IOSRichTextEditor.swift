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

        init(statistics: EditorStatistics) {
            self.statistics = statistics
            super.init()
        }

        override func makeEditorView(for note: NoteItem) -> UIView {
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
            guard let textView = editorView as? MarkdownTextView else { return }

            textView.text = text
            textView.undoManager?.removeAllActions()  // clear undo history on load

            textView.restyle()
        }

        /// Applies the note's mode and the app-wide zoom. Repaints only — the text is not read,
        /// not rewritten, and the saver is not told anything, because nothing changed.
        override func configure(_ editorView: UIView, appearance: MarkdownStyling.Appearance) {
            guard let textView = editorView as? MarkdownTextView else { return }

            textView.styling = appearance
            textView.restyle()
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

        override func statsDidChange(_ stats: TextStats) {
            statistics.stats = stats
        }

        /// Continues or ends a list when Return is pressed on one. See the macOS editor for
        /// why declining the newline here is safe against re-entry.
        func textView(
            _ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String
        ) -> Bool {
            guard text == "\n",
                let edit = ListContinuation.returnEdit(
                    in: (textView.text ?? "") as NSString, selectedRange: range)
            else { return true }

            textView.apply(edit)
            return false
        }

        func textViewDidChange(_ textView: UITextView) {
            guard let textView = textView as? MarkdownTextView else { return }

            // The storage has already repainted itself by now — the text view is its own
            // storage delegate. Only the typing attributes are left to put back.
            textView.resetTypingAttributes()
            textDidChange(text: textView.text ?? "")
        }
    }
}

/// The editor's text view, with markdown styling painted on from its text.
class MarkdownTextView: UITextView, NSTextStorageDelegate {
    /// How this view draws. Display only — none of it is ever stored.
    var styling = MarkdownStyling.Appearance(
        plainText: false, fontSize: AppConstants.Layout.defaultFontSize)

    /// Repaints the whole note, for when every line's appearance changes at once — a mode
    /// switch, a zoom step, or freshly loaded text.
    ///
    /// The selection is restored around the repaint. Setting attributes across the whole
    /// document leaves it alone on macOS, but UIKit collapses it to the end. The line-scoped
    /// repaint below does not need this: it never touches the whole document.
    func restyle() {
        let selection = selectedRange

        MarkdownStyling.apply(styling, to: textStorage)
        resetTypingAttributes()

        if selectedRange != selection {
            selectedRange = selection
        }
    }

    /// Repaints the lines an edit landed on. See the macOS twin.
    ///
    /// `NSTextStorage.EditActions` here where AppKit spells the same type
    /// `NSTextStorageEditActions` — the one place the two editors cannot share a signature.
    func textStorage(
        _ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorage.EditActions,
        range editedRange: NSRange, changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }

        MarkdownStyling.apply(styling, to: textStorage, over: editedRange)
    }

    /// Typing attributes are not part of the storage, so no repaint of it can cover them —
    /// they are the half of #117 that undo does not restore.
    func resetTypingAttributes() {
        typingAttributes = MarkdownStyling.baseAttributes(styling)
    }
}
