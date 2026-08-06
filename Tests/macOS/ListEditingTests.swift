import AppKit
import SwiftUI
import Testing

@testable import Heptad

/// The list rules applied to a real `NSTextView`: that Return reaches them through the editor
/// delegate, that ⌘⇧U reaches the checkbox one, and — the part the rules themselves cannot
/// show — that each edit lands on the undo stack as a single step.
///
/// `ListContinuationTests` covers which edit each rule produces.
@MainActor
final class ListEditingTests {
    /// The app's own text view, not a bare `NSTextView`: a plain one takes its undo manager
    /// from the window it is in, and there is no window here. `IsolatedUndoTextView` carries
    /// the per-note manager the undo assertions below are about.
    private let textView: IsolatedUndoTextView
    private let coordinator: MacRichTextEditor.Coordinator
    private let scratchDefaults: ScratchDefaults
    private let manager: EditorShortcutManager

    init() throws {
        textView = IsolatedUndoTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        textView.isRichText = true
        textView.allowsUndo = true

        coordinator = makeTestCoordinator()
        textView.delegate = coordinator

        // A scratch suite, so a killed run cannot leave state in the real app's defaults.
        scratchDefaults = try ScratchDefaults(name: "ListEditingTests")
        manager = EditorShortcutManager(defaults: scratchDefaults.defaults)
    }

    /// Return as the text view delivers it: the delegate is asked first, and answering false
    /// is what replaces the newline with the continuation.
    @discardableResult
    private func pressReturn() -> Bool {
        coordinator.textView(
            textView, shouldChangeTextIn: textView.selectedRange(), replacementString: "\n")
    }

    private func type(_ text: String) {
        textView.string = text
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
    }

    // MARK: - Return

    @Test func returnOnAnEmptyItemEndsTheList() {
        type("- item\n- ")

        #expect(pressReturn() == false)
        #expect(textView.string == "- item\n")
    }

    /// Return anywhere else is left to the text view, which is what inserts the newline.
    @Test func returnOffAListIsPassedThrough() {
        type("plain text")

        #expect(pressReturn())
        #expect(textView.string == "plain text")
    }

    // MARK: - ⌘⇧U

    @Test func toggleCheckboxFlipsTheBoxOnTheCaretsLine() {
        type("- [ ] task")

        manager.toggleCheckbox(on: textView)
        #expect(textView.string == "- [x] task")

        manager.toggleCheckbox(on: textView)
        #expect(textView.string == "- [ ] task")
    }

    @Test func toggleCheckboxLeavesALineWithoutABoxAlone() {
        type("- item")

        manager.toggleCheckbox(on: textView)

        #expect(textView.string == "- item")
    }

    /// ⌘⇧U reaches the toggle only with shift held; plain ⌘U belongs to the text view.
    @Test func shiftCommandUReachesTheToggle() throws {
        type("- [ ] task")
        let event = try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: 0,
                windowNumber: 0, context: nil, characters: "U", charactersIgnoringModifiers: "U",
                isARepeat: false, keyCode: 32))

        let consumed = manager.handleTextViewShortcut(
            chars: "U", hasShift: true, on: textView, event: event)

        #expect(consumed == nil, "The shortcut is handled here, not passed on")
        #expect(textView.string == "- [x] task")
    }

    // MARK: - Undo

    /// The acceptance criterion the rules cannot show on their own: every mutation goes
    /// through the text view's change hooks, so one undo takes back exactly one step.
    @Test func undoReversesEachEditOnItsOwn() {
        type("- item")

        pressReturn()
        #expect(textView.string == "- item\n- ")

        textView.undoManager?.undo()
        #expect(textView.string == "- item")
    }

    @Test func undoReversesACheckboxToggle() {
        type("- [ ] task")

        manager.toggleCheckbox(on: textView)
        #expect(textView.string == "- [x] task")

        textView.undoManager?.undo()
        #expect(textView.string == "- [ ] task")
    }
}
