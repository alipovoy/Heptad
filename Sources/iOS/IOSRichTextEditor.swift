import SwiftUI
import UIKit

struct IOSRichTextEditor: UIViewRepresentable {
    var note: NoteItem

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()

        textView.delegate = context.coordinator
        textView.allowsEditingTextAttributes = true
        textView.font = .systemFont(ofSize: 18)
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
        private var saveTask: Task<Void, Never>?

        init(_ parent: IOSRichTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            // Cancel previous debounce task
            saveTask?.cancel()

            // Snapshot the attributed string on the main thread
            let attrString = NSAttributedString(attributedString: textView.attributedText)

            saveTask = Task {
                // Debounce window (300ms)
                try? await Task.sleep(nanoseconds: AppConstants.Timing.debounceSaveNanoseconds)
                guard !Task.isCancelled else { return }

                // Serialize off the main thread
                let rtfData = await Task.detached(priority: .userInitiated) {
                    let range = NSRange(location: 0, length: attrString.length)
                    return try? attrString.data(
                        from: range,
                        documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
                    )
                }.value

                guard !Task.isCancelled, let data = rtfData else { return }

                // Update SwiftData model on MainActor
                await MainActor.run {
                    self.parent.note.rtfData = data
                }
            }
        }
    }
}
