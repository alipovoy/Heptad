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
struct ListEditingTests {
    /// The app's own text view, not a bare `NSTextView`: a plain one takes its undo manager
    /// from the window it is in, and there is no window here. `MarkdownTextView` carries
    /// the per-note manager the undo assertions below are about.
    private let textView: MarkdownTextView
    private let coordinator: MacRichTextEditor.Coordinator
    private let scratchDefaults: ScratchDefaults
    private let notificationCenter = NotificationCenter()
    private let manager: EditorShortcutManager

    init() throws {
        textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        textView.isRichText = true
        textView.allowsUndo = true

        // A scratch suite, so neither a killed run nor the coordinator's zoom read touches the real
        // app's defaults.
        scratchDefaults = try ScratchDefaults(name: "ListEditingTests")
        coordinator = makeTestCoordinator(
            defaults: scratchDefaults.defaults, notificationCenter: notificationCenter)
        textView.delegate = coordinator

        manager = EditorShortcutManager(
            notificationCenter: notificationCenter, defaults: scratchDefaults.defaults)
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

    /// The same view holding `markdown` as formatted text: delimiters gone, traits on the
    /// characters. `type` above gives a flat buffer, which cannot show what an inserted marker
    /// inherits.
    private func load(_ markdown: String) {
        textView.apply(
            MarkdownStyling.Appearance(
                plainText: false, fontSize: AppConstants.Layout.defaultFontSize))
        textView.load(markdown: markdown)
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
    }

    private func isBold(at location: Int) throws -> Bool {
        let storage = try #require(textView.textStorage)
        let font = try #require(storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont)
        return font.isBold
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

    // MARK: - Markers are syntax, not formatting

    /// Return at the end of a formatted item gives the next one a plain marker.
    ///
    /// A bare string inserted into an attributed buffer inherits the run it lands in, so the new
    /// `- ` came out bold — `**-** ` in the store, which is not a list marker at all, so Return
    /// would not continue it and ⌘⇧U would find no checkbox on it.
    @Test(arguments: [
        ("- **item**", "- item\n- ", "- **item**\n- "),
        ("1. **a**", "1. a\n2. ", "1. **a**\n2. "),
        ("- item **x**", "- item x\n- ", "- item **x**\n- "),
        ("- [ ] **task**", "- [ ] task\n- [ ] ", "- [ ] **task**\n- [ ] ")
    ])
    func returnAfterAFormattedItemLeavesTheNewMarkerUnformatted(
        markdown: String, buffer: String, stored: String
    ) throws {
        load(markdown)

        #expect(pressReturn() == false)
        #expect(textView.string == buffer)
        #expect(try isBold(at: textView.string.utf16.count - 1) == false, "the marker is plain")
        #expect(textView.markdown == stored, "so the new line is still a list item in the store")
    }

    /// And the checkbox character is part of a marker too, so flipping one in a formatted item
    /// does not paint the box with the run it sits beside.
    @Test func flippingACheckboxOnAFormattedItemKeepsTheBoxPlain() throws {
        load("- [ ] **task**")

        manager.toggleCheckbox(on: textView)

        #expect(textView.string == "- [x] task")
        #expect(try isBold(at: 3) == false, "the box itself is not formatting")
        #expect(textView.markdown == "- [x] **task**")
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

    /// ⌘⇧U reaches the toggle only with shift held; the plain form is checked below. `chars` comes
    /// out lowercase even though the event types "U": `commandKey` folds case, and `hasShift` is
    /// what reports shift to the table.
    @Test func shiftCommandUReachesTheToggle() throws {
        type("- [ ] task")
        let event = try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: 0,
                windowNumber: 0, context: nil, characters: "U", charactersIgnoringModifiers: "U",
                isARepeat: false, keyCode: 32))

        let consumed = manager.handleTextViewShortcut(
            chars: KeyboardLayout.commandKey(for: event), hasShift: true, on: textView,
            event: event)

        #expect(consumed == nil, "The shortcut is handled here, not passed on")
        #expect(textView.string == "- [x] task")
    }

    /// The other side of that `where hasShift`: losing it would make plain ⌘U flip checkboxes.
    /// Nothing else claims the key either — a markdown note has no underline to give — so it
    /// reaches no command at all, which only a test of the unshifted form can pin.
    @Test func plainCommandUIsHandedBack() throws {
        type("- [ ] task")
        let event = try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                windowNumber: 0, context: nil, characters: "u", charactersIgnoringModifiers: "u",
                isARepeat: false, keyCode: 32))

        let consumed = manager.handleTextViewShortcut(
            chars: "u", hasShift: false, on: textView, event: event)

        #expect(consumed != nil, "Plain ⌘U is not the app's key and must be handed back")
        #expect(textView.string == "- [ ] task", "The box is left as it was")
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
