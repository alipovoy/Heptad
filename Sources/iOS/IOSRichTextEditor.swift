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
            textView.allowsEditingTextAttributes = true
            textView.font = .systemFont(ofSize: AppConstants.Layout.defaultFontSize)
            textView.backgroundColor = .clear

            // Apply text padding
            textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

            if let attrString = note.attributedContent {
                textView.attributedText = attrString
                textView.undoManager?.removeAllActions()  // clear undo history on load
            }
            return textView
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

        func textViewDidChange(_ textView: UITextView) {
            // Snapshot the attributed string on the main thread
            textDidChange(
                attributedString: NSAttributedString(attributedString: textView.attributedText),
                plainText: textView.text ?? "")
        }
    }
}
