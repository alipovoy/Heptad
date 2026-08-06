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
            let textView = UITextView()

            textView.delegate = self

            // A new text view is a rich one. `configure` is what makes it plain — see the note
            // in `MacRichTextEditor`.
            textView.allowsEditingTextAttributes = true
            textView.font = .editorBody(plainText: false)
            textView.backgroundColor = .clear

            // Apply text padding
            textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

            return textView
        }

        override func load(_ content: NSAttributedString?, into editorView: UIView) {
            guard let content, let textView = editorView as? UITextView else { return }

            textView.attributedText = content
            textView.undoManager?.removeAllActions()  // clear undo history on load
        }

        /// Switches the visible text view between rich and plain, flattening what is already
        /// there. `allowsEditingTextAttributes` is the applied state, so this is a no-op until
        /// the note's mode actually changes.
        override func configure(_ editorView: UIView, for note: NoteItem) {
            guard let textView = editorView as? UITextView,
                textView.allowsEditingTextAttributes == note.isPlainText
            else { return }

            textView.allowsEditingTextAttributes = !note.isPlainText

            let attributes = PlainTextMode.attributes(plainText: note.isPlainText)
            textView.typingAttributes = attributes

            // Nothing to flatten and, more to the point, nothing to report: this also runs on a
            // view that has just been created and has not been loaded yet, and telling the saver
            // about an empty view would debounce a write that empties the note. macOS returns
            // here for the same reason.
            let flattened = NSMutableAttributedString(attributedString: textView.attributedText)
            guard flattened.length > 0 else { return }

            flattened.setAttributes(
                attributes, range: NSRange(location: 0, length: flattened.length))

            // Assigning `attributedText` resets both of these, so they are restored after it.
            let selection = textView.selectedRange
            textView.attributedText = flattened
            textView.selectedRange = selection
            textView.typingAttributes = attributes

            // Assigning the text does not call the delegate, so the saver is told directly —
            // otherwise the flattening would sit in the view until the next keystroke.
            textDidChange(attributedString: flattened, plainText: textView.text ?? "")
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
            // `attributedText` already hands back a copy, so wrapping it in another one made
            // two per keystroke where the saver needs none of its own.
            textDidChange(
                attributedString: textView.attributedText, plainText: textView.text ?? "")
        }
    }
}
