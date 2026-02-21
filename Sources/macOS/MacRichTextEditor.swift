import SwiftUI
import AppKit

struct MacRichTextEditor: NSViewRepresentable {
    var note: NoteItem

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        textView.allowsUndo = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsImageEditing = false
        textView.font = .systemFont(ofSize: 16)

        textView.usesInspectorBar = false
        textView.allowsDocumentBackgroundColorChange = false
        textView.backgroundColor = .clear
        textView.drawsBackground = false

        // Apply text padding
        textView.textContainerInset = NSSize(width: 8, height: 8)

        if !note.rtfData.isEmpty,
           let attrString = NSAttributedString(rtf: note.rtfData, documentAttributes: nil) {
            // Disable undo registration during initial content load.
            // setAttributedString opens undo groups that cause
            // "too many nested undo groups" crash if not properly closed.
            textView.undoManager?.disableUndoRegistration()
            textView.textStorage?.setAttributedString(attrString)
            textView.undoManager?.enableUndoRegistration()
            textView.undoManager?.removeAllActions()
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        // Handled entirely by recreating view via .id(note.id) in ContentView
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MacRichTextEditor
        private var saveTask: Task<Void, Never>?

        init(_ parent: MacRichTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            guard let textStorage = textView.textStorage else { return }

            // Cancel previous debounce task
            saveTask?.cancel()

            // Snapshot the attributed string on the main thread
            let attrString = NSAttributedString(attributedString: textStorage)

            saveTask = Task {
                // Debounce window (300ms)
                try? await Task.sleep(nanoseconds: 300_000_000)
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
