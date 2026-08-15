import AppKit
import Testing

@testable import Heptad

// The stand-ins `EditorShortcutManagerTests` drives the dispatch table against. Split out of that
// file so the tests are the file: what these record is one question ("which command did the key
// reach?") and it is answered the same way for all of them.
//
// Not `private`, because they are used from another file now — which is also why the spy text view
// is `final` and its `record` stays as narrow as the subclassing allows.

/// Records the editing commands `handleTextViewShortcut` dispatches instead of running them.
///
/// Two reasons for the stand-in rather than a real `NSTextView`: `copy`/`cut`/`paste` go through
/// `NSPasteboard.general`, so running them for real would trample the clipboard of whoever is
/// running the tests; and the dispatch table is only interesting if a test can tell *which*
/// command a keystroke reached, which is the bug class the table invites (a swapped `case`, or a
/// `where hasShift` that should be `where !hasShift`).
///
/// Commands are recorded as plain strings so the enum doesn't have to leak into the signature of
/// a parameterized test — a private type there would force the test itself to be private.
///
/// A `MarkdownTextView` rather than a bare `NSTextView`, because the formatting and paste
/// commands ask the view which mode it is in. Standing in for a view the app never installs
/// would put every one of them on the plain-text branch, and the suite would pass while
/// asserting nothing.
final class SpyTextView: MarkdownTextView {
    private(set) var commands: [String] = []
    private lazy var spyUndoManager = SpyUndoManager { [weak self] in self?.record($0) }

    /// An `NSTextView` only gets a real undo manager once it is in a window; the spy stands in
    /// for one so ⌘Z/⌘⇧Z can be observed without building a window per case.
    override var undoManager: UndoManager? { spyUndoManager }

    fileprivate func record(_ command: String) { commands.append(command) }

    override func copy(_ sender: Any?) { record("copy") }
    override func cut(_ sender: Any?) { record("cut") }
    override func paste(_ sender: Any?) { record("paste") }
    override func selectAll(_ sender: Any?) { record("selectAll") }
}

/// Records the app-level actions ⌘Q and ⌘W ask for, instead of quitting the test process or
/// closing whichever window another suite left key.
@MainActor
final class SpyAppCommander: AppCommanding {
    private(set) var performed: [String] = []

    nonisolated init() {}

    func terminate() { performed.append("terminate") }
    func closeKeyWindow() { performed.append("closeKeyWindow") }
}

final class SpyUndoManager: UndoManager {
    private let onCommand: (String) -> Void

    init(onCommand: @escaping (String) -> Void) {
        self.onCommand = onCommand
        super.init()
    }

    override func undo() { onCommand("undo") }
    override func redo() { onCommand("redo") }
}
