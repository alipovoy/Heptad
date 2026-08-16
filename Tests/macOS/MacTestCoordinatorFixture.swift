import AppKit

@testable import Heptad

/// The coordinator every editing fixture in this directory needs: `PlainTextModeTests` and
/// `ListEditingTests` each drive a real `NSTextView` through it rather than poking the view
/// directly, so `EditorStatistics` is the only thing they ever need to supply.
///
/// `statistics` is handed in when the caller wants to read the counts back, since the coordinator
/// holds it privately.
///
/// `defaults` and `notificationCenter` have no default values on purpose. Under
/// `TEST_HOST = Heptad.app` a `.standard` here is the shipping `dev.lipovoy.heptad.mac` domain, and
/// the coordinator reads `editorFontSize` out of it on the way to every appearance; a `.default`
/// centre likewise makes one `.flushPendingSaves` post reach every saver in the process.
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
