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

    override init() {
        super.init()

        // No removeObserver needed: selector-based observers auto-unregister on deinit.
        NotificationCenter.default.addObserver(
            self, selector: #selector(discardEditorViews), name: .notesDidRestore, object: nil)
    }

    /// Throws the cached views away so the next update rebuilds them from the notes.
    ///
    /// A restore rewrites `rtfData` underneath views that are already installed and showing
    /// the old text; nothing about a model write reaches an AppKit or UIKit text view. The
    /// savers are kept — they hold the same `NoteItem` objects, which are still current.
    ///
    /// `@objc` selector dispatch does not hop actors, so this cannot be isolated directly.
    /// The only poster is `ContentView`, on the main actor.
    @objc nonisolated private func discardEditorViews() {
        MainActor.assumeIsolated {
            for view in editorViews.values {
                view.removeFromSuperview()
            }
            editorViews.removeAll()
            currentNoteId = nil
        }
    }

    func setup(container: PlatformView, notes: [NoteItem], selectedIndex: Int) {
        self.container = container
        update(notes: notes, selectedIndex: selectedIndex)
    }

    func update(notes: [NoteItem], selectedIndex: Int) {
        guard notes.indices.contains(selectedIndex) else { return }
        let note = notes[selectedIndex]

        if currentNoteId == note.id {
            // Already showing, but its settings may have just changed — the plain-text toggle
            // acts on the note, not on the view, and the view is cached across updates.
            if let editorView = editorViews[note.id] {
                configure(editorView, for: note)
            }
            return
        }

        guard let container else { return }

        // Remove previous note's view, gracefully resigning first responder
        if let oldId = currentNoteId, let oldView = editorViews[oldId] {
            resignFocus(from: oldView)
            oldView.removeFromSuperview()
        }

        // Before anything below can build or configure a view: applying a note's mode is a text
        // edit, and it reports itself back through `textDidChange`, which looks the saver up by
        // the *current* note. Set at the end of this method instead, that lookup would find the
        // note being left and write the incoming note's text into it.
        currentNoteId = note.id

        let editorView: PlatformView
        if let cached = editorViews[note.id] {
            editorView = cached

            // On this path too, not only on the early return above: a cached view whose note
            // changed mode while it was off screen would otherwise come back in the old one.
            // A new view is configured inside `makeCachedEditorView`, which has to do it at a
            // particular point in the build.
            configure(editorView, for: note)
        } else {
            editorView = makeCachedEditorView(for: note)
        }

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

        updateStats(plainText: plainText(of: editorView), for: note.id)
    }

    /// Builds the note's editor view and its saver, and caches both.
    ///
    /// The order here is the whole reason this is not three lines inline. The saver has to
    /// exist before `configure` can route a flattening edit to it. `configure` has to run
    /// before the content is loaded, because it flattens whatever is already in the view —
    /// against an empty view it only sets the mode, which leaves the note's own attributes to
    /// arrive intact with `load`.
    private func makeCachedEditorView(for note: NoteItem) -> PlatformView {
        let editorView = makeEditorView(for: note)
        editorViews[note.id] = editorView
        savers[note.id] = NoteContentSaver(note: note)

        configure(editorView, for: note)
        load(note.attributedContent, into: editorView)
        return editorView
    }

    /// Called by the platform delegate methods when the visible note's text changes.
    func textDidChange(attributedString: NSAttributedString, plainText: String) {
        guard let noteId = currentNoteId, let saver = savers[noteId] else { return }
        saver.save(attributedString: attributedString)

        // The title's only input is this text, so handing it over here is what keeps the cache
        // from having to decode the RTF the saver is about to write.
        NoteTitleCache.shared.record(plainText: plainText, for: noteId)
        updateStats(plainText: plainText, for: noteId)
    }

    /// Counts characters/words/lines off the main actor so large notes don't stall typing,
    /// then delivers the result back on the main actor. Detached deliberately: a plain
    /// `Task {}` here would inherit this class's MainActor isolation and run inline.
    ///
    /// Nothing orders these tasks against each other, so two quick note switches can deliver the
    /// older count last and leave the bar showing the previous note's numbers until the next
    /// keystroke. `noteId` is the note the text was read from, and it is re-checked against the
    /// showing note on delivery so a result that has been overtaken is dropped.
    ///
    /// Passed in rather than read off `currentNoteId` here: the `update` path counts the incoming
    /// note's text *before* it becomes the current one, so reading it would name the note being
    /// left and drop every count taken on a switch.
    private func updateStats(plainText: String, for noteId: Int) {
        Task.detached(priority: .utility) { [weak self] in
            let stats = TextStats(text: plainText)
            await self?.deliverStats(stats, for: noteId)
        }
    }

    /// Hands `stats` to the platform hook, unless the note moved on while they were being counted.
    private func deliverStats(_ stats: TextStats, for noteId: Int) {
        guard noteId == currentNoteId else { return }
        statsDidChange(stats)
    }

    // MARK: - Platform hooks

    /// Creates the view to install for the given note: the editor's chrome, in the state a new
    /// rich-text view starts in. The note's own mode and content arrive through `configure` and
    /// `load`, which is what keeps either of them from having a second implementation here.
    func makeEditorView(for note: NoteItem) -> PlatformView {
        fatalError("Subclasses must override makeEditorView(for:)")
    }

    /// Applies a note's own settings — plain-text mode today — to a view.
    ///
    /// Runs on every install and on every update of the showing note, so it must be inert when
    /// the mode has not moved: it reads the applied state back off the view and returns when
    /// that already matches. Left unguarded it would re-flatten a rich note on every keystroke.
    func configure(_ editorView: PlatformView, for note: NoteItem) {}

    /// Puts the note's stored content into a view that has just been created and configured.
    func load(_ content: NSAttributedString?, into editorView: PlatformView) {}

    func resignFocus(from editorView: PlatformView) {}

    func focus(_ editorView: PlatformView) {}

    func plainText(of editorView: PlatformView) -> String { "" }

    func statsDidChange(_ stats: TextStats) {}
}
