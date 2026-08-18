import AppKit
import Testing

@testable import Heptad

/// ⌘⌫, which is `NSTextView`'s own "delete to beginning of line" and not the app's.
///
/// It used to be Clear Note — the whole buffer, wherever the caret was. That is a key every
/// other editor spends on one line, and a note is emptied with ⌘A ⌫ in two keystrokes, so the
/// command was dropped rather than moved. These tests exist to keep the key unclaimed: the
/// dispatch table is what took it, and the table is where it would be taken again.
@MainActor
struct DeleteToLineStartTests {
    private let textView: MarkdownTextView
    private let scratchDefaults: ScratchDefaults
    private let manager: EditorShortcutManager

    init() throws {
        textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        textView.allowsUndo = true
        textView.string = "user: admin\npass: rotate-me"

        textView.delegate = makeTestCoordinator()

        scratchDefaults = try ScratchDefaults(name: "DeleteToLineStartTests")
        manager = EditorShortcutManager(defaults: scratchDefaults.defaults)
    }

    private func commandDelete(shift: Bool = false) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero,
                modifierFlags: shift ? [.command, .shift] : [.command], timestamp: 0,
                windowNumber: 0, context: nil, characters: "\u{7F}",
                charactersIgnoringModifiers: "\u{7F}", isARepeat: false, keyCode: 51))
    }

    /// The event is handed back rather than consumed, which is the whole of the change: the
    /// text view is what acts on it, and it deletes to the start of the caret's line.
    @Test(arguments: [false, true])
    func commandDeleteIsPassedToTheTextView(shift: Bool) throws {
        let event = try commandDelete(shift: shift)

        let consumed = manager.handleTextViewShortcut(
            chars: "\u{7F}", hasShift: shift, on: textView, event: event)

        #expect(consumed === event, "⌘⌫ is not the app's key")
        #expect(textView.string == "user: admin\npass: rotate-me", "and nothing acted on it here")
    }

    /// What the text view then does with it, driven directly — the selector is the one AppKit
    /// binds ⌘⌫ to, and it is the behaviour the shortcut used to cost.
    @Test func deletingToTheLineStartLeavesTheRestOfTheNote() {
        textView.setSelectedRange(NSRange(location: 18, length: 0))  // after "pass: "

        textView.deleteToBeginningOfLine(nil)

        #expect(textView.string == "user: admin\nrotate-me")
    }

    @Test func theCaretAtTheStartOfALineDeletesNothing() {
        textView.setSelectedRange(NSRange(location: 12, length: 0))  // head of line 2

        textView.deleteToBeginningOfLine(nil)

        #expect(textView.string == "user: admin\npass: rotate-me")
    }
}
