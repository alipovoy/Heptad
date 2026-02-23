import SwiftUI
import UIKit

struct IOSRichTextEditor: UIViewRepresentable {
    var note: NoteItem

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()

        textView.delegate = context.coordinator
        textView.allowsEditingTextAttributes = true
        textView.font = .systemFont(ofSize: AppConstants.UI.defaultFontSize)
        textView.backgroundColor = .clear

        // Apply text padding
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

        if !note.rtfData.isEmpty,
           let attrString = try? NSAttributedString(
                data: note.rtfData,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
           ) {
            textView.attributedText = attrString
        }

        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        // Handled entirely by recreating view via .id(note.id) in ContentView
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: IOSRichTextEditor
        private let saver: NoteContentSaver

        init(_ parent: IOSRichTextEditor) {
            self.parent = parent
            self.saver = NoteContentSaver(note: parent.note)
        }

        func textViewDidChange(_ textView: UITextView) {
            // Snapshot the attributed string on the main thread
            let attrString = NSAttributedString(attributedString: textView.attributedText)

            saver.save(attributedString: attrString)
        }
    }
}
