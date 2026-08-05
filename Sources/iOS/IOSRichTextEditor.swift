import SwiftUI
import UIKit

struct IOSRichTextEditor: UIViewRepresentable {
    var notes: [NoteItem]
    @Binding var selectedNoteIndex: Int
    @Binding var textStats: TextStats

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        context.coordinator.setup(container: container, notes: notes, selectedIndex: selectedNoteIndex)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // See the note in MacRichTextEditor: the coordinator would otherwise hold the struct
        // instance from `makeCoordinator` for the life of the app.
        context.coordinator.parent = self
        context.coordinator.update(notes: notes, selectedIndex: selectedNoteIndex)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NoteEditorCoordinator, UITextViewDelegate {
        var parent: IOSRichTextEditor

        init(_ parent: IOSRichTextEditor) {
            self.parent = parent
        }

        override func makeEditorView(for note: NoteItem) -> UIView {
            let textView = UITextView()

            textView.delegate = self
            // Plain mode is attribute editing off, which is also what makes paste unstyled.
            textView.allowsEditingTextAttributes = !note.isPlainText
            textView.font = .editorBody(plainText: note.isPlainText)
            textView.backgroundColor = .clear

            // Apply text padding
            textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

            if let attrString = note.attributedContent {
                textView.attributedText = attrString
                textView.undoManager?.removeAllActions()  // clear undo history on load
            }
            return textView
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
            let flattened = NSMutableAttributedString(attributedString: textView.attributedText)
            if flattened.length > 0 {
                flattened.setAttributes(
                    attributes, range: NSRange(location: 0, length: flattened.length))
            }

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
            parent.textStats = stats
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
            // Snapshot the attributed string on the main thread
            textDidChange(
                attributedString: NSAttributedString(attributedString: textView.attributedText),
                plainText: textView.text ?? "")
        }
    }
}
