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
    private var pendingText: String?

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

    /// Debounces the write of `text` to the note.
    func save(text: String) {
        saveTask?.cancel()
        pendingText = text

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
        guard let pending = pendingText else { return }
        performSave(text: pending)
        pendingText = nil
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
