import AppKit
import SwiftUI
import Testing

@testable import Heptad

/// Clearing a note: the ⌘⌫ shortcut, the context-menu item beside it, and the undo that makes
/// an accidental clear cheap again.
@MainActor
struct ClearNoteTests {
    /// The app's text view rather than a bare one — a plain `NSTextView` takes its undo
    /// manager from a window, and there is none here.
    private let textView: MarkdownTextView
    private let coordinator: MacRichTextEditor.Coordinator
    private let scratchDefaults: ScratchDefaults
    private let manager: EditorShortcutManager

    init() throws {
        textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        textView.allowsUndo = true
        textView.string = "user: admin\npass: rotate-me"

        coordinator = makeTestCoordinator()
        textView.delegate = coordinator

        scratchDefaults = try ScratchDefaults(name: "ClearNoteTests")
        manager = EditorShortcutManager(defaults: scratchDefaults.defaults)
    }

    private func keyEvent(characters: String, shift: Bool = false) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero,
                modifierFlags: shift ? [.command, .shift] : [.command], timestamp: 0,
                windowNumber: 0, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 51))
    }

    // MARK: - Clearing

    @Test func clearingEmptiesTheNote() {
        textView.clearNote()

        #expect(textView.string.isEmpty)
    }

    @Test func clearingAnEmptyNoteDoesNothing() {
        textView.string = ""

        textView.clearNote()

        #expect(textView.string.isEmpty)
    }

    // MARK: - Reaching it

    @Test func commandDeleteClearsTheNote() throws {
        let consumed = manager.handleTextViewShortcut(
            chars: "\u{7F}", hasShift: false, on: textView, event: try keyEvent(characters: "\u{7F}"))

        #expect(consumed == nil, "The shortcut is handled here, not passed to the text view")
        #expect(textView.string.isEmpty)
    }

    /// ⇧⌘⌫ is not ours; it has to reach the text view like any other unclaimed key.
    @Test func shiftCommandDeleteIsPassedThrough() throws {
        let event = try keyEvent(characters: "\u{7F}", shift: true)

        let consumed = manager.handleTextViewShortcut(
            chars: "\u{7F}", hasShift: true, on: textView, event: event)

        #expect(consumed === event)
        #expect(textView.string.isEmpty == false)
    }

    /// The context menu carries the same action, since there is no main menu to put it in.
    @Test func theContextMenuOffersClearNote() throws {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Copy", action: nil, keyEquivalent: ""))

        let returned = try #require(
            coordinator.textView(
                textView, menu: menu, for: try keyEvent(characters: "\u{7F}"), at: 0))
        let item = try #require(returned.items.last)

        #expect(item.title == "Clear Note")

        NSApp.sendAction(try #require(item.action), to: item.target, from: item)
        #expect(textView.string.isEmpty)
    }

    // MARK: - Undo

    /// The point of routing the clear through the change hooks: an accidental ⌘⌫ costs one ⌘Z.
    @Test func undoBringsTheNoteBack() {
        let original = textView.string

        textView.clearNote()
        #expect(textView.string.isEmpty)

        textView.undoManager?.undo()

        #expect(textView.string == original)
    }
}
