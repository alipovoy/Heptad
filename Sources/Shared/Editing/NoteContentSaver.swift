import Foundation

extension Notification.Name {
    static let flushPendingSaves = Notification.Name("Heptad.flushPendingSaves")
}

/// Debounces writes of a note's markdown back to the store.
@MainActor
class NoteContentSaver {
    private var saveTask: Task<Void, Never>?
    private let note: NoteItem
    private let debounce: Duration
    private let maxDelay: Duration

    /// When the current run of unbroken typing began, or nil when there is no save pending.
    private var burstStartedAt: ContinuousClock.Instant?

    /// How to read the text when the debounce is up, rather than the text itself. In formatted
    /// mode producing it means writing the whole buffer out as markdown, and a keystroke should
    /// not pay for a save that has not happened yet — most of them are overtaken by the next one.
    private var pendingText: (@MainActor () -> String?)?

    init(
        note: NoteItem,
        debounce: Duration = AppConstants.Timing.debounceSave,
        maxDelay: Duration = AppConstants.Timing.maxSaveDelay,
        notificationCenter: NotificationCenter = .default
    ) {
        self.note = note
        self.debounce = debounce
        self.maxDelay = maxDelay

        // No removeObserver needed: selector-based observers auto-unregister on deinit.
        notificationCenter.addObserver(
            self,
            selector: #selector(flush),
            name: .flushPendingSaves,
            object: nil
        )
    }

    /// Debounces the write of `text` to the note.
    func save(text: String) {
        save { text }
    }

    /// Debounces a write, reading the text when the write actually happens.
    ///
    /// The debounce is what keeps a save from being paid per keystroke, and the ceiling is what
    /// keeps it from never being paid at all: every keystroke restarts the timer, so typing
    /// faster than the debounce leaves the whole burst in the text view and nowhere else. The
    /// wait is whichever of the two comes first.
    func save(_ text: @escaping @MainActor () -> String?) {
        saveTask?.cancel()
        pendingText = text

        let started = burstStartedAt ?? .now
        burstStartedAt = started
        let wait = min(debounce, maxDelay - started.duration(to: .now))

        saveTask = Task {
            try? await Task.sleep(for: max(wait, .zero))
            guard !Task.isCancelled else { return }

            burstStartedAt = nil
            flushPending()
        }
    }

    /// Immediately saves any pending text and cancels the debounced task.
    ///
    /// `@objc` selector dispatch (used by `NotificationCenter`) crosses the Swift/ObjC
    /// boundary without hopping actors, so this can't be `@MainActor`-isolated directly.
    /// `assumeIsolated` documents the requirement and traps immediately if a future caller
    /// ever posts `.flushPendingSaves` from a background thread, instead of racing silently.
    @objc nonisolated func flush() {
        MainActor.assumeIsolated {
            saveTask?.cancel()
            saveTask = nil
            burstStartedAt = nil
            flushPending()
        }
    }

    private func flushPending() {
        guard let pending = pendingText else { return }
        pendingText = nil

        // nil means the editor the text would have come from is gone. Skipped rather than
        // treated as empty: writing "" here would clear the note it was supposed to save.
        guard let text = pending() else { return }
        performSave(text: text)
    }

    private func performSave(text: String) {
        // Skip the SwiftData write when unchanged.
        let stored = NoteItem.storedText(from: text)
        guard stored != note.text else { return }

        note.text = stored
        // Only reached when the content actually changed, so the guard above keeps
        // `modifiedAt` from drifting on no-op saves (flushes, reopening a note).
        note.modifiedAt = .now
    }
}
