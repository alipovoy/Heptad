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
        }

        override func makeEditorView(for note: NoteItem) -> UIView {
            let textView = MarkdownTextView()

            textView.delegate = self

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
        override func configure(_ editorView: UIView, for note: NoteItem) {
            guard let textView = editorView as? MarkdownTextView else { return }

            textView.styling = MarkdownStyling.Appearance(plainText: note.isPlainText)
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

            // Before the report, not after: `restyle` is what erases anything a paste brought
            // with it, and the string handed on below is what gets saved.
            textView.restyle()
            textDidChange(text: textView.text ?? "")
        }
    }
}

/// The editor's text view, with markdown styling painted on from its text.
class MarkdownTextView: UITextView {
    /// How this view draws. Display only — none of it is ever stored.
    var styling = MarkdownStyling.Appearance(plainText: false)

    /// Repaints the note's styling from its own text.
    ///
    /// See the macOS twin for why this runs after every change rather than only on demand: it
    /// is what puts both the storage's attributes and `typingAttributes` back under this app's
    /// control, instead of trusting what a paste or an undo left behind (#117).
    ///
    /// The selection is restored around the repaint. Mutating `textStorage` attributes leaves it
    /// alone on macOS, but UIKit collapses it to the end of the document.
    func restyle() {
        let selection = selectedRange

        MarkdownStyling.apply(styling, to: textStorage)
        typingAttributes = MarkdownStyling.baseAttributes(styling)

        if selectedRange != selection {
            selectedRange = selection
        }
    }
}
