import AppKit

@testable import Heptad

/// The coordinator every editing fixture in this directory needs: `PlainTextModeTests`,
/// `ListEditingTests` and `ClearNoteTests` each drive a real `NSTextView` through it rather than
/// poking the view directly, so `EditorStatistics` is the only thing they ever need to supply.
@MainActor
func makeTestCoordinator() -> MacRichTextEditor.Coordinator {
    MacRichTextEditor.Coordinator(statistics: EditorStatistics())
}
