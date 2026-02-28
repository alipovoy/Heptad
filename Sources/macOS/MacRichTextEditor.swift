import AppKit
import SwiftUI

struct MacRichTextEditor: NSViewRepresentable {
    var notes: [NoteItem]
    @Binding var selectedNoteIndex: Int
    @Binding var textStats: TextStats

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        context.coordinator.setup(container: container)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(notes: notes, selectedIndex: selectedNoteIndex)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MacRichTextEditor
        weak var container: NSView?

        private var scrollViews: [Int: NSScrollView] = [:]
        private var textViews: [Int: NSTextView] = [:]
        private var savers: [Int: NoteContentSaver] = [:]

        private var currentNoteId: Int?

        init(_ parent: MacRichTextEditor) {
            self.parent = parent
        }

        func setup(container: NSView) {
            self.container = container
            update(notes: parent.notes, selectedIndex: parent.selectedNoteIndex)
        }

        func update(notes: [NoteItem], selectedIndex: Int) {
            guard selectedIndex >= 0 && selectedIndex < notes.count else { return }
            let note = notes[selectedIndex]

            if currentNoteId == note.id {
                return  // already showing
            }

            guard let container = container else { return }

            // Remove previous note's view
            if let oldId = currentNoteId, let oldScrollView = scrollViews[oldId] {
                // Gracefully resign first responder from the old text view
                if let oldTextView = textViews[oldId],
                    let window = container.window,
                    window.firstResponder == oldTextView
                {
                    window.makeFirstResponder(container)
                }
                oldScrollView.removeFromSuperview()
            }

            // Create views for the new note lazily if they don't exist yet
            if scrollViews[note.id] == nil {
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

                    if !note.rtfData.isEmpty,
                        let attrString = NSAttributedString(
                            rtf: note.rtfData, documentAttributes: nil)
                    {
                        textView.undoManager?.disableUndoRegistration()
                        textView.textStorage?.setAttributedString(attrString)
                        textView.undoManager?.enableUndoRegistration()
                        textView.undoManager?.removeAllActions()
                    }

                    textViews[note.id] = textView
                }

                scrollViews[note.id] = scrollView
                savers[note.id] = NoteContentSaver(note: note)
            }

            // Add and show the new note's view
            if let scrollView = scrollViews[note.id], let textView = textViews[note.id] {
                scrollView.translatesAutoresizingMaskIntoConstraints = false
                container.addSubview(scrollView)

                NSLayoutConstraint.activate([
                    scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                    scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                    scrollView.topAnchor.constraint(equalTo: container.topAnchor),
                    scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                ])

                // Focus the text view when it appears (e.g. after tapping a note circle) so user can type immediately.
                DispatchQueue.main.async {
                    scrollView.window?.makeFirstResponder(textView)
                }

                TextStatisticsCalculator.calculate(for: textView.string) { [weak self] stats in
                    self?.parent.textStats = stats
                }
            }

            currentNoteId = note.id
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            guard let textStorage = textView.textStorage else { return }

            // Find which note this text view belongs to
            guard let noteId = textViews.first(where: { $0.value == textView })?.key else { return }
            guard let saver = savers[noteId] else { return }

            // Snapshot the attributed string on the main thread
            let attrString = NSAttributedString(attributedString: textStorage)

            saver.save(attributedString: attrString)

            TextStatisticsCalculator.calculate(for: textView.string) { [weak self] stats in
                self?.parent.textStats = stats
            }
        }
    }
}

class IsolatedUndoTextView: NSTextView {
    private let customUndoManager = UndoManager()

    override var undoManager: UndoManager? {
        return customUndoManager
    }
}
