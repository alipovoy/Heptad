import Foundation

/// A shared utility class to handle debouncing and RTF serialization for rich text editors.
class NoteContentSaver {
    private var saveTask: Task<Void, Never>?
    private let note: NoteItem
    private let debounceNanoseconds: UInt64

    init(note: NoteItem, debounceNanoseconds: UInt64 = AppConstants.Timing.debounceSaveNanoseconds) {
        self.note = note
        self.debounceNanoseconds = debounceNanoseconds
    }

    /// Snapshots the attributed string and debounces serialization and saving.
    func save(attributedString: NSAttributedString) {
        saveTask?.cancel()

        saveTask = Task {
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            guard !Task.isCancelled else { return }

            // Serialize off the main thread
            let rtfData = await Task.detached(priority: .userInitiated) {
                let range = NSRange(location: 0, length: attributedString.length)
                return try? attributedString.data(
                    from: range,
                    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
                )
            }.value

            guard !Task.isCancelled, let data = rtfData else { return }

            // Update SwiftData model
            await MainActor.run {
                self.note.rtfData = data
            }
        }
    }
}
