import SwiftUI

#if canImport(UIKit)
    import UIKit
    typealias PlatformView = UIView
#else
    import AppKit
    typealias PlatformView = NSView
#endif

/// Platform-neutral core shared by the macOS and iOS rich text editor coordinators.
/// Caches one editor view and one saver per note, swaps the visible note's view in
/// the container, and routes text changes to debounced saves and statistics updates.
/// Subclasses provide view creation, focus handling, and text access.
@MainActor
class NoteEditorCoordinator: NSObject {
    private(set) weak var container: PlatformView?
    private var editorViews: [Int: PlatformView] = [:]
    private var savers: [Int: NoteContentSaver] = [:]
    private(set) var currentNoteId: Int?

    func setup(container: PlatformView, notes: [NoteItem], selectedIndex: Int) {
        self.container = container
        update(notes: notes, selectedIndex: selectedIndex)
    }

    func update(notes: [NoteItem], selectedIndex: Int) {
        guard notes.indices.contains(selectedIndex) else { return }
        let note = notes[selectedIndex]

        if currentNoteId == note.id {
            return  // already showing
        }

        guard let container else { return }

        // Remove previous note's view, gracefully resigning first responder
        if let oldId = currentNoteId, let oldView = editorViews[oldId] {
            resignFocus(from: oldView)
            oldView.removeFromSuperview()
        }

        // Create views for the new note lazily if they don't exist yet
        if editorViews[note.id] == nil {
            editorViews[note.id] = makeEditorView(for: note)
            savers[note.id] = NoteContentSaver(note: note)
        }

        // Add and show the new note's view
        if let editorView = editorViews[note.id] {
            editorView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(editorView)

            NSLayoutConstraint.activate([
                editorView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                editorView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                editorView.topAnchor.constraint(equalTo: container.topAnchor),
                editorView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])

            // Focus the text view when it appears (e.g. after tapping a note circle) so user can type immediately.
            Task {
                focus(editorView)
            }

            updateStats(plainText: plainText(of: editorView))
        }

        currentNoteId = note.id
    }

    /// Called by the platform delegate methods when the visible note's text changes.
    func textDidChange(attributedString: NSAttributedString, plainText: String) {
        guard let noteId = currentNoteId, let saver = savers[noteId] else { return }
        saver.save(attributedString: attributedString)
        updateStats(plainText: plainText)
    }

    /// Counts characters/words/lines off the main actor so large notes don't stall typing,
    /// then delivers the result back on the main actor. Detached deliberately: a plain
    /// `Task {}` here would inherit this class's MainActor isolation and run inline.
    private func updateStats(plainText: String) {
        Task.detached(priority: .utility) { [weak self] in
            let stats = TextStats(text: plainText)
            await self?.statsDidChange(stats)
        }
    }

    // MARK: - Platform hooks

    /// Creates and configures the view to install for the given note (including loading its content).
    func makeEditorView(for note: NoteItem) -> PlatformView {
        fatalError("Subclasses must override makeEditorView(for:)")
    }

    func resignFocus(from editorView: PlatformView) {}

    func focus(_ editorView: PlatformView) {}

    func plainText(of editorView: PlatformView) -> String { "" }

    func statsDidChange(_ stats: TextStats) {}
}
