import AppKit

@testable import Heptad

/// The coordinator every editing fixture in this directory needs: `PlainTextModeTests` and
/// `ListEditingTests` each drive a real `NSTextView` through it rather than poking the view
/// directly, so `EditorStatistics` is the only thing they ever need to supply.
///
/// Handed in rather than made here when the caller wants to read the counts back: the coordinator
/// holds it privately, and it is the only place the statistics it reports can be observed.
@MainActor
func makeTestCoordinator(
    statistics: EditorStatistics? = nil
) -> MacRichTextEditor.Coordinator {
    MacRichTextEditor.Coordinator(statistics: statistics ?? EditorStatistics())
}
