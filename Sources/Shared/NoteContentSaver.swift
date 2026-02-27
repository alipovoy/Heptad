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

            await MainActor.run {
                guard !Task.isCancelled else { return }

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
    }
}
