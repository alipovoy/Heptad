import Foundation

extension Notification.Name {
    static let flushPendingSaves = Notification.Name("SevenNotes.flushPendingSaves")
}

/// A shared utility class to handle debouncing and RTF serialization for rich text editors.
class NoteContentSaver {
    private var saveTask: Task<Void, Never>?
    private let note: NoteItem
    private let debounceNanoseconds: UInt64
    private var pendingAttributedString: NSAttributedString?

    init(note: NoteItem, debounceNanoseconds: UInt64 = AppConstants.Timing.debounceSaveNanoseconds) {
        self.note = note
        self.debounceNanoseconds = debounceNanoseconds

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(flush),
            name: .flushPendingSaves,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Snapshots the attributed string and debounces serialization and saving.
    func save(attributedString: NSAttributedString) {
        saveTask?.cancel()
        pendingAttributedString = attributedString

        saveTask = Task {
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard !Task.isCancelled else { return }

                if let pending = self.pendingAttributedString {
                    self.performSave(attributedString: pending)
                    self.pendingAttributedString = nil
                }
            }
        }
    }

    /// Immediately saves any pending text and cancels the debounced task.
    @objc func flush() {
        guard let pending = pendingAttributedString else { return }
        saveTask?.cancel()
        saveTask = nil

        if Thread.isMainThread {
            self.performSave(attributedString: pending)
        } else {
            DispatchQueue.main.sync {
                self.performSave(attributedString: pending)
            }
        }
        pendingAttributedString = nil
    }

    private func performSave(attributedString: NSAttributedString) {
        let isEmpty = attributedString.length == 0
            || attributedString.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        let rtfData: Data?
        if isEmpty {
            rtfData = Data()
        } else {
            let range = NSRange(location: 0, length: attributedString.length)
            rtfData = try? attributedString.data(
                from: range,
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
        }

        if let data = rtfData {
            self.note.rtfData = data
        }
    }
}
