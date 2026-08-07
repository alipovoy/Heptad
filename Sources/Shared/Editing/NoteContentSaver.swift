import Foundation

extension Notification.Name {
    static let flushPendingSaves = Notification.Name("Heptad.flushPendingSaves")
}

/// A shared utility class to handle debouncing and RTF serialization for rich text editors.
@MainActor
class NoteContentSaver {
    private var saveTask: Task<Void, Never>?
    private let note: NoteItem
    private let debounce: Duration
    private var pendingAttributedString: NSAttributedString?

    init(
        note: NoteItem,
        debounce: Duration = AppConstants.Timing.debounceSave,
        notificationCenter: NotificationCenter = .default
    ) {
        self.note = note
        self.debounce = debounce

        // No removeObserver needed: selector-based observers auto-unregister on deinit.
        notificationCenter.addObserver(
            self,
            selector: #selector(flush),
            name: .flushPendingSaves,
            object: nil
        )
    }

    /// Debounces serialization and saving of `attributedString`.
    ///
    /// The argument may be the text view's own storage rather than a copy of it. Copying every
    /// character and every attribute run on each keystroke, only for all but the last copy in a
    /// 300 ms window to be thrown away by the next `save`, is the cost this avoids.
    ///
    /// What that changes: the RTF written is the text as of the *flush*, not as of this call.
    /// Both run on the main actor, and any keystroke in between would have replaced the copy
    /// anyway, so what lands in the note is the same either way.
    func save(attributedString: NSAttributedString) {
        saveTask?.cancel()
        pendingAttributedString = attributedString

        saveTask = Task {
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
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
            flushPending()
        }
    }

    private func flushPending() {
        guard let pending = pendingAttributedString else { return }
        performSave(attributedString: pending)
        pendingAttributedString = nil
    }

    private func performSave(attributedString: NSAttributedString) {
        // Keep the previous data when encoding fails; skip the SwiftData write when unchanged.
        guard let data = NoteItem.rtfData(from: attributedString), data != note.rtfData else {
            return
        }
        note.rtfData = data
        // Only reached when the content actually changed, so the guard above keeps
        // `modifiedAt` from drifting on no-op saves (flushes, reopening a note).
        note.modifiedAt = .now
    }
}
