import SwiftUI

#if canImport(UIKit)
    import UIKit
    typealias PlatformView = UIView
#else
    import AppKit
    typealias PlatformView = NSView
#endif

/// Platform-neutral core shared by the macOS and iOS editor coordinators.
/// Caches one editor view and one saver per note, swaps the visible note's view in
/// the container, and routes text changes to debounced saves and statistics updates.
/// Subclasses provide view creation, focus handling, and text access.
@MainActor
class NoteEditorCoordinator: NSObject {
    private(set) weak var container: PlatformView?
    private var editorViews: [Int: PlatformView] = [:]
    private var savers: [Int: NoteContentSaver] = [:]
    private(set) var currentNoteId: Int?

    /// Each note's mode, by id, so a font-size change can repaint every cached view without
    /// waiting for SwiftUI to drive one through.
    ///
    /// Modes rather than the notes themselves: `configure` asks a note for `isPlainText` and
    /// nothing else, so keeping the models alive only to look one flag up would retain seven
    /// managed objects for the coordinator's lifetime as a lookup table.
    private var modes: [Int: Bool] = [:]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, notificationCenter: NotificationCenter = .default) {
        self.defaults = defaults
        super.init()

        // No removeObserver needed: selector-based observers auto-unregister on deinit. Same
        // pattern, and the same reason, as `NoteContentSaver`.
        //
        // The same centre the zoom is posted on, and the same defaults it is read from: half an
        // injection seam is worse than none, because it reads as tested when it is not.
        notificationCenter.addObserver(
            self, selector: #selector(editorFontSizeDidChange),
            name: .editorFontSizeDidChange, object: nil)
    }

    /// How a note should be drawn right now: its own mode, at the app-wide zoom.
    func appearance(forNoteId id: Int) -> MarkdownStyling.Appearance {
        MarkdownStyling.Appearance(
            plainText: modes[id] ?? false, fontSize: EditorFontSize.current(defaults))
    }

    func setup(container: PlatformView, notes: [NoteItem], selectedIndex: Int) {
        self.container = container
        update(notes: notes, selectedIndex: selectedIndex)
    }

    func update(notes: [NoteItem], selectedIndex: Int) {
        guard notes.indices.contains(selectedIndex) else { return }
        for note in notes { modes[note.id] = note.isPlainText }
        let note = notes[selectedIndex]

        if currentNoteId == note.id {
            // Already showing, but its settings may have just changed — the plain-text toggle
            // acts on the note, not on the view, and the view is cached across updates.
            if let editorView = editorViews[note.id] {
                configure(editorView, appearance: appearance(forNoteId: note.id))
            }
            return
        }

        guard let container else { return }

        // Remove previous note's view, gracefully resigning first responder
        if let oldId = currentNoteId, let oldView = editorViews[oldId] {
            resignFocus(from: oldView)
            oldView.removeFromSuperview()
        }

        // Before anything below can build a view: `load` puts text into one, and any report that
        // reaches `textDidChange` looks the saver up by the *current* note. Set at the end of
        // this method instead, that lookup would find the note being left and write the incoming
        // note's text into it.
        currentNoteId = note.id

        let editorView: PlatformView
        if let cached = editorViews[note.id] {
            editorView = cached

            // On this path too, not only on the early return above: a cached view whose note
            // changed mode while it was off screen would otherwise come back in the old one.
            // A new view is configured inside `makeCachedEditorView`, which has to do it at a
            // particular point in the build.
            configure(editorView, appearance: appearance(forNoteId: note.id))
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
    /// `configure` before `load`: the view has to know how it draws before there is anything in
    /// it to draw, or the first paint would use the wrong mode until the next keystroke.
    private func makeCachedEditorView(for note: NoteItem) -> PlatformView {
        let editorView = makeEditorView(for: note)
        editorViews[note.id] = editorView
        savers[note.id] = NoteContentSaver(note: note)

        configure(editorView, appearance: appearance(forNoteId: note.id))
        load(note.text, into: editorView)
        return editorView
    }

    /// Repaints every cached note at the new zoom level.
    ///
    /// `@objc` selector dispatch (used by `NotificationCenter`) crosses the Swift/ObjC boundary
    /// without hopping actors, so this can't be `@MainActor`-isolated directly. The poster is
    /// the key monitor, which is already on the main actor.
    @objc nonisolated private func editorFontSizeDidChange() {
        MainActor.assumeIsolated {
            for (id, editorView) in editorViews {
                configure(editorView, appearance: appearance(forNoteId: id))
            }
        }
    }

    /// Called by the platform delegate methods when the visible note's text changes.
    ///
    /// One string now, where this used to take the attributed storage as well: the note *is* its
    /// text, so the saver and the counters read the same thing.
    func textDidChange(text: String) {
        guard let noteId = currentNoteId, let saver = savers[noteId] else { return }
        saver.save(text: text)

        updateStats(plainText: text, for: noteId)
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
    /// text view starts in. The note's own mode and content arrive through `configure` and
    /// `load`, which is what keeps either of them from having a second implementation here.
    func makeEditorView(for note: NoteItem) -> PlatformView {
        fatalError("Subclasses must override makeEditorView(for:)")
    }

    /// Applies a note's mode, and the app-wide zoom, to a view.
    ///
    /// Runs on every install and on every update of the showing note. It no longer needs to
    /// guard against running twice: this repaints derived styling and never touches the text,
    /// so calling it on every keystroke would be wasteful but not wrong. Under attributed
    /// storage it flattened the note, and an unguarded call was destructive.
    ///
    /// Takes the appearance rather than the note: how a view draws is all this decides, and
    /// asking for the model would put a `NoteItem` on the zoom-notification path, which has no
    /// note in hand.
    func configure(_ editorView: PlatformView, appearance: MarkdownStyling.Appearance) {}

    /// Puts the note's markdown into a view that has just been created and configured.
    func load(_ text: String, into editorView: PlatformView) {}

    func resignFocus(from editorView: PlatformView) {}

    func focus(_ editorView: PlatformView) {}

    func plainText(of editorView: PlatformView) -> String { "" }

    func statsDidChange(_ stats: TextStats) {}
}
