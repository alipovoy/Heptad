import AppKit
import SwiftUI

struct MacRichTextEditor: NSViewRepresentable {
    var notes: [NoteItem]
    @Binding var selectedNoteIndex: Int
    @Binding var textStats: TextStats

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        context.coordinator.setup(container: container, notes: notes, selectedIndex: selectedNoteIndex)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(notes: notes, selectedIndex: selectedNoteIndex)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NoteEditorCoordinator, NSTextViewDelegate {
        var parent: MacRichTextEditor

        init(_ parent: MacRichTextEditor) {
            self.parent = parent
        }

        override func makeEditorView(for note: NoteItem) -> NSView {
            let scrollView = IsolatedUndoTextView.scrollableTextView()
            scrollView.borderType = .noBorder
            scrollView.drawsBackground = false

            if let textView = scrollView.documentView as? IsolatedUndoTextView {
                textView.delegate = self
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

                if let attrString = note.attributedContent {
                    textView.undoManager?.disableUndoRegistration()
                    textView.textStorage?.setAttributedString(attrString)
                    textView.undoManager?.enableUndoRegistration()
                    textView.undoManager?.removeAllActions()
                }
            }
            return scrollView
        }

        override func resignFocus(from editorView: NSView) {
            if let textView = textView(in: editorView),
                let window = editorView.window,
                window.firstResponder == textView
            {
                window.makeFirstResponder(container)
            }
        }

        override func focus(_ editorView: NSView) {
            if let textView = textView(in: editorView) {
                editorView.window?.makeFirstResponder(textView)
            }
        }

        override func plainText(of editorView: NSView) -> String {
            textView(in: editorView)?.string ?? ""
        }

        override func statsDidChange(_ stats: TextStats) {
            parent.textStats = stats
        }

        private func textView(in editorView: NSView) -> NSTextView? {
            (editorView as? NSScrollView)?.documentView as? NSTextView
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                let textStorage = textView.textStorage
            else { return }

            // Snapshot the attributed string on the main thread
            textDidChange(
                attributedString: NSAttributedString(attributedString: textStorage),
                plainText: textView.string)
        }
    }
}

class IsolatedUndoTextView: NSTextView {
    private let customUndoManager = UndoManager()

    override var undoManager: UndoManager? {
        return customUndoManager
    }
}
