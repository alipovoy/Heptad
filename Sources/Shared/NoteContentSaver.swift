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

    /// Snapshots the attributed string and debounces serialization and saving.
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
    }
}
