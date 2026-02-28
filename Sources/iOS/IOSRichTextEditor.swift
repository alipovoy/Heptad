import SwiftUI
import UIKit

struct IOSRichTextEditor: UIViewRepresentable {
    var notes: [NoteItem]
    @Binding var selectedNoteIndex: Int
    @Binding var textStats: TextStats

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        context.coordinator.setup(container: container)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.update(notes: notes, selectedIndex: selectedNoteIndex)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: IOSRichTextEditor
        weak var container: UIView?

        private var textViews: [Int: UITextView] = [:]
        private var savers: [Int: NoteContentSaver] = [:]

        private var currentNoteId: Int?

        init(_ parent: IOSRichTextEditor) {
            self.parent = parent
        }

        func setup(container: UIView) {
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
            if let oldId = currentNoteId, let oldTextView = textViews[oldId] {
                // Gracefully resign first responder from the old text view
                if oldTextView.isFirstResponder {
                    oldTextView.resignFirstResponder()
                }
                oldTextView.removeFromSuperview()
            }

            // Create views for the new note lazily if they don't exist yet
            if textViews[note.id] == nil {
                let textView = UITextView()

                textView.delegate = self
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
                    textView.undoManager?.removeAllActions() // clear undo history on load
                }

                textViews[note.id] = textView
                savers[note.id] = NoteContentSaver(note: note)
            }

            // Add and show the new note's view
            if let textView = textViews[note.id] {
                textView.translatesAutoresizingMaskIntoConstraints = false
                container.addSubview(textView)

                NSLayoutConstraint.activate([
                    textView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                    textView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                    textView.topAnchor.constraint(equalTo: container.topAnchor),
                    textView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                ])

                // Focus the text view when it appears (e.g. after tapping a note circle) so user can type immediately.
                DispatchQueue.main.async {
                    textView.becomeFirstResponder()
                }

                TextStatisticsCalculator.calculate(for: textView.text ?? "") { [weak self] stats in
                    self?.parent.textStats = stats
                }
            }

            currentNoteId = note.id
        }

        func textViewDidChange(_ textView: UITextView) {
            // Find which note this text view belongs to
            guard let noteId = textViews.first(where: { $0.value === textView })?.key else { return }
            guard let saver = savers[noteId] else { return }

            // Snapshot the attributed string on the main thread
            let attrString = NSAttributedString(attributedString: textView.attributedText)

            saver.save(attributedString: attrString)

            TextStatisticsCalculator.calculate(for: textView.text ?? "") { [weak self] stats in
                self?.parent.textStats = stats
            }
        }
    }
}
