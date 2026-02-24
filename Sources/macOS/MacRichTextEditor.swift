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
        textView.font = .systemFont(ofSize: AppConstants.UI.defaultFontSize)

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

        // Focus the text view when it appears (e.g. after tapping a note circle) so user can type immediately.
        DispatchQueue.main.async {
            scrollView.window?.makeFirstResponder(textView)
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
        private let saver: NoteContentSaver

        init(_ parent: MacRichTextEditor) {
            self.parent = parent
            self.saver = NoteContentSaver(note: parent.note)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            guard let textStorage = textView.textStorage else { return }

            // Snapshot the attributed string on the main thread
            let attrString = NSAttributedString(attributedString: textStorage)

            saver.save(attributedString: attrString)
        }
    }
}
