import AppKit

@testable import Heptad

/// The coordinator every editing fixture in this directory needs: `PlainTextModeTests` and
/// `ListEditingTests` each drive a real `NSTextView` through it rather than poking the view
/// directly, so `EditorStatistics` is the only thing they ever need to supply.
///
/// Handed in rather than made here when the caller wants to read the counts back: the coordinator
/// holds it privately, and it is the only place the statistics it reports can be observed.
///
/// `defaults` and `notificationCenter` have no defaults on purpose. Under `TEST_HOST = Heptad.app`
/// a `.standard` here is the shipping `dev.lipovoy.heptad.mac` domain, and the coordinator reads
/// `editorFontSize` out of it on the way to every appearance: four tests asserting a font size
/// agreed with the fixture's hardcoded default only while nobody had ever pressed ⌘+ in the real
/// app. `.default` for the centre is the same shape — it makes one `.flushPendingSaves` post reach
/// every saver in the process.
@MainActor
func makeTestCoordinator(
    statistics: EditorStatistics? = nil,
    defaults: UserDefaults,
    notificationCenter: NotificationCenter
) -> MacRichTextEditor.Coordinator {
    MacRichTextEditor.Coordinator(
        statistics: statistics ?? EditorStatistics(), defaults: defaults,
        notificationCenter: notificationCenter)
}
