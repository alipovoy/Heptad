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

    /// Each note's mode, by id, so `appearance(forNoteId:)` can answer with no `NoteItem` in
    /// hand — the zoom repaint has an id and nothing else.
    ///
    /// Two flags rather than the notes themselves, which is a smaller table and not a lighter one:
    /// `savers` holds a `NoteItem` per visited note for the coordinator's whole life anyway. This
    /// used to claim it avoided that retention.
    private var modes: [Int: Bool] = [:]

    /// Each note's palette index — its position in the array everything above this class
    /// addresses notes by.
    ///
    /// Held rather than derived from the id. This is the one component that addresses a note by
    /// `id`, and the two agree only while the stored ids are exactly `0..<noteCount`; where they
    /// came apart, `NotePalette.boldTint` clamped rather than failed, so bold text came up in
    /// another note's colour with nothing to say which.
    private var paletteIndices: [Int: Int] = [:]

    /// The count in flight, held so the next keystroke can cancel it.
    private var statsTask: Task<Void, Never>?

    private let defaults: UserDefaults

    /// Held, not merely observed on: the savers below are built with it too. Passing them
    /// `.default` while this class listened on an injected centre made the injection a half
    /// measure — a test could only flush a coordinator-built saver by posting process-wide, which
    /// reaches every saver of every coordinator alive anywhere in the process.
    private let notificationCenter: NotificationCenter

    init(defaults: UserDefaults = .standard, notificationCenter: NotificationCenter = .default) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
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

    /// How a note should be drawn right now: its own mode, at the app-wide zoom, in its own
    /// colour, all three looked up here rather than threaded down alongside the note.
    ///
    /// A note with no recorded palette index gets no tint rather than someone else's. It cannot
    /// happen — `update` records one for every note before anything is configured — and an
    /// untinted appearance is no longer a value the text views need this never to produce: they
    /// hold their own as `nil` until configured, so the first call lands whatever it carries.
    func appearance(forNoteId id: Int) -> MarkdownStyling.Appearance {
        MarkdownStyling.Appearance(
            plainText: modes[id] ?? false, fontSize: EditorFontSize.current(defaults),
            tintedNoteIndex: paletteIndices[id])
    }

    func setup(container: PlatformView, notes: [NoteItem], selectedIndex: Int) {
        self.container = container
        update(notes: notes, selectedIndex: selectedIndex)
    }

    /// `selectedIndex` must be a valid index into `notes`. Both representables take the two from
    /// the same `ContentView` body, where the selection is clamped against that very array — see
    /// `NoteSelection`. Guarding again here would be a second answer to the same question, and
    /// the answer it used to give was to install no editor at all: a blank, untypable note
    /// beside a statistics bar describing a different one.
    func update(notes: [NoteItem], selectedIndex: Int) {
        for (index, note) in notes.enumerated() {
            modes[note.id] = note.isPlainText
            paletteIndices[note.id] = index
        }
        let note = notes[selectedIndex]

        if currentNoteId == note.id {
            // Already showing, but its settings may have just changed — the plain-text toggle
            // acts on the note, not on the view, and the view is cached across updates.
            if let editorView = editorViews[note.id] {
                configure(editorView, appearance: appearance(forNoteId: note.id))

                // A mode step rewrites the buffer, and the counters describe what is on screen.
                // Nothing else refreshes them on this path: the conversion goes through
                // `setAttributedString`, which reports to the storage delegate and not to
                // `textDidChange`, so the bar kept the other mode's numbers until the next
                // keystroke.
                updateStats(plainText: plainText(of: editorView), for: note.id)
            }
            return
        }

        guard let container else { return }

        // Remove previous note's view, gracefully resigning first responder
        if let oldId = currentNoteId, let oldView = editorViews[oldId] {
            resignFocus(from: oldView)
            oldView.removeFromSuperview()
        }

        // Before anything below can build a view, so nothing under it can act on a stale answer
        // to "which note is showing". Measured: neither `configure` nor `load` reports through
        // `textDidChange` — both go through `setAttributedString`, which tells the storage
        // delegate and no one else — so the cross-note write this used to claim to prevent
        // cannot happen. Kept because a lookup naming the note being left is a bad shape, not
        // because anything is currently reaching for one.
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
    /// `configure` before `load`, and the reason is narrower than "the first paint would be
    /// wrong": on an empty buffer `apply`'s whole body is inert — the normalize returns on a
    /// zero length, and the typing attributes it sets are overwritten by `load` two lines later.
    /// What survives is that it records the appearance, which is what `load` then renders
    /// through. Reverse the two and the note is rendered in whatever the view was before.
    private func makeCachedEditorView(for note: NoteItem) -> PlatformView {
        let editorView = makeEditorView()
        editorViews[note.id] = editorView
        savers[note.id] = NoteContentSaver(note: note, notificationCenter: notificationCenter)

        configure(editorView, appearance: appearance(forNoteId: note.id))
        load(note.text, into: editorView)
        return editorView
    }

    /// Repaints the showing note at the new zoom level.
    ///
    /// Only the showing one. Every cached view is configured again on its way back in (#103), so
    /// repainting the other six here does work that is thrown away and then done a second time —
    /// with seven 300-line notes cached that measured 155 ms per `⌘+`, against the 33 ms a key
    /// repeat leaves, six sevenths of it spent on notes nobody was looking at.
    ///
    /// `@objc` selector dispatch (used by `NotificationCenter`) crosses the Swift/ObjC boundary
    /// without hopping actors, so this can't be `@MainActor`-isolated directly. The poster is
    /// the key monitor, which is already on the main actor.
    @objc nonisolated private func editorFontSizeDidChange() {
        MainActor.assumeIsolated {
            guard let noteId = currentNoteId, let editorView = editorViews[noteId] else { return }

            configure(editorView, appearance: appearance(forNoteId: noteId))
        }
    }

    /// Called by the platform delegate methods when the visible note's text changes.
    ///
    /// The two readings of "the text" have come apart, and this is where that shows: the counters
    /// want what is on screen, and the store wants markdown, which in formatted mode means
    /// writing the buffer out. The markdown is fetched as a closure rather than produced here, so
    /// that walk happens once per debounce window instead of once per keystroke.
    func noteDidChange() {
        guard let noteId = currentNoteId, let editorView = editorViews[noteId],
            let saver = savers[noteId]
        else { return }

        saver.save { [weak self, weak editorView] in
            guard let self, let editorView else { return nil }
            return markdown(of: editorView)
        }

        updateStats(plainText: plainText(of: editorView), for: noteId)
    }

    /// Counts characters/words/lines off the main actor so large notes don't stall typing,
    /// then delivers the result back on the main actor. Detached deliberately: a plain
    /// `Task {}` here would inherit this class's MainActor isolation and run inline.
    ///
    /// The previous count is cancelled, because only the last one can be right. Nothing did that
    /// before, so three seconds of typing on a 145 KB note started fifty full-note scans — about
    /// half a second of CPU, forty-nine of whose results were thrown away — six lines under a
    /// *save* that is debounced for exactly this reason. Three numbers in a bar need freshness
    /// less than the store does, not more.
    ///
    /// Cancellation is checked on delivery rather than inside the count: `TextStats` is one pass
    /// with no allocation, and threading a check through it would cost more than it saves on
    /// every note small enough for the scan to finish anyway.
    ///
    /// `noteId` is the note the text was read from, re-checked against the showing note on
    /// delivery — passed in rather than read off `currentNoteId` there, because the `update` path
    /// counts the incoming note's text *before* it becomes the current one.
    private func updateStats(plainText: String, for noteId: Int) {
        statsTask?.cancel()
        statsTask = Task.detached(priority: .utility) { [weak self] in
            let stats = TextStats(text: plainText)
            guard !Task.isCancelled else { return }

            await self?.deliverStats(stats, for: noteId)
        }
    }

    /// Hands `stats` to the platform hook, unless the note moved on while they were being counted.
    private func deliverStats(_ stats: TextStats, for noteId: Int) {
        guard noteId == currentNoteId else { return }
        statsDidChange(stats)
    }

    // MARK: - Platform hooks

    /// Creates the view to install: the editor's chrome, in the state a new text view starts in.
    ///
    /// Takes no note, and that is the contract rather than an omission — a note's mode and
    /// content arrive through `configure` and `load`, which is what keeps either of them from
    /// having a second implementation here. It used to take one that neither platform read.
    func makeEditorView() -> PlatformView {
        fatalError("Subclasses must override makeEditorView()")
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

    /// What the view is showing, for the counters.
    func plainText(of editorView: PlatformView) -> String { "" }

    /// The same note as markdown, for the store. In plain mode the two are the same string; in
    /// formatted mode this is the buffer written back out — see `MarkdownWriting`.
    func markdown(of editorView: PlatformView) -> String { "" }

    func statsDidChange(_ stats: TextStats) {}
}
