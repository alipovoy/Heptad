import Foundation

/// Defines a common requirement for the note object that will be updated by the saver.
protocol MutableNoteItem: AnyObject {
    var rtfData: Data { get set }
}

// Since NoteItem is a SwiftData model, it already is a reference type (class).
// We update `NoteItem` in `Schema.swift` or where it's defined to conform to this or just use it directly.
// Given we know it's `NoteItem`, we can just use `NoteItem` directly to avoid protocol boxing issues with SwiftData.

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
