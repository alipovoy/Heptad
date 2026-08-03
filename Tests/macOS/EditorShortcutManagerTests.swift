import AppKit
import SwiftData
import Testing

@testable import Heptad

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
private final class SpyTextView: NSTextView {
    private(set) var commands: [String] = []
    private lazy var spyUndoManager = SpyUndoManager { [weak self] in self?.record($0) }

    /// An `NSTextView` only gets a real undo manager once it is in a window; the spy stands in
    /// for one so ⌘Z/⌘⇧Z can be observed without building a window per case.
    override var undoManager: UndoManager? { spyUndoManager }

    fileprivate func record(_ command: String) { commands.append(command) }

    override func copy(_ sender: Any?) { record("copy") }
    override func cut(_ sender: Any?) { record("cut") }
    override func paste(_ sender: Any?) { record("paste") }
    override func pasteAsPlainText(_ sender: Any?) { record("pasteAsPlainText") }
    override func selectAll(_ sender: Any?) { record("selectAll") }
}

private final class SpyUndoManager: UndoManager {
    private let onCommand: (String) -> Void

    init(onCommand: @escaping (String) -> Void) {
        self.onCommand = onCommand
        super.init()
    }

    override func undo() { onCommand("undo") }
    override func redo() { onCommand("redo") }
}

/// `NSTextView` and friends are main-actor types, and the suite drives them directly.
@MainActor
final class EditorShortcutManagerTests {
    private let suiteName: String
    private let defaults: UserDefaults
    private let textView: SpyTextView
    private let manager: EditorShortcutManager

    init() throws {
        // A scratch suite rather than `.standard`: `selectNote` writes the selected note index,
        // and a killed test run would otherwise leave the real app pointing at another note.
        suiteName = "EditorShortcutManagerTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))

        textView = SpyTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        textView.string = "Test Text"
        textView.textStorage?.addAttribute(
            .font, value: NSFont.systemFont(ofSize: 14), range: NSRange(location: 0, length: 9))

        manager = EditorShortcutManager(defaults: defaults)
    }

    /// `isolated` so the AppKit teardown runs on the main actor wherever the last release lands.
    isolated deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - Fixtures

    /// A stand-in key event. `handleTextViewShortcut` never inspects it — it only hands it back
    /// unchanged for the shortcuts it doesn't claim — so any key event will do.
    private func passThroughEvent() throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                windowNumber: 0, context: nil, characters: "k", charactersIgnoringModifiers: "k",
                isARepeat: false, keyCode: 40))
    }

    /// The font on the first character, where every formatting assertion below looks.
    private func selectionFont() throws -> NSFont {
        let storage = try #require(textView.textStorage, "Missing text storage")
        return try #require(
            storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont,
            "Missing font attribute")
    }

    private func selectionStrikethrough() throws -> Int {
        let storage = try #require(textView.textStorage, "Missing text storage")
        return (storage.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int) ?? 0
    }

    /// A scratch store, so the ⌘0 path never opens — let alone reads — the developer's notes.
    private func inMemoryContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: NoteItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    // MARK: - Dispatch table
    //
    // The table is a flat `switch` over characters and shift, and every arm returns nil. Nothing
    // else in the suite can tell a mis-keyed arm from a correct one, so it is pinned three ways:
    // which keys are consumed at all, which text-view command each one reaches, and what the
    // formatting arms do to the selection.

    @Test(
        arguments: [
            ("b", false, true), ("b", true, false),
            ("i", false, true), ("i", true, false),
            // ⌘+ on a US keyboard arrives as ⌘⇧=, so the size arms accept shift.
            ("+", false, true), ("=", false, true), ("=", true, true), ("-", false, true),
            ("z", false, true), ("z", true, true), ("Z", false, true),
            ("c", false, true), ("c", true, false),
            ("v", false, true), ("v", true, true), ("V", false, true),
            // The sharp one: ⌘⇧X is strikethrough, plain ⌘X is cut.
            ("x", false, true), ("x", true, true), ("X", false, true),
            ("a", false, true), ("a", true, false),
            ("k", false, false), ("k", true, false)
        ])
    func dispatchTableConsumesExactlyTheKeysItHandles(
        chars: String, hasShift: Bool, isConsumed: Bool
    ) throws {
        textView.setSelectedRange(NSRange(location: 0, length: 4))  // "Test"

        let result = manager.handleTextViewShortcut(
            chars: chars, hasShift: hasShift, on: textView, event: try passThroughEvent())

        #expect(
            (result == nil) == isConsumed,
            "A consumed shortcut returns nil; anything else must hand the event back")
    }

    @Test(
        arguments: [
            ("z", false, "undo"), ("z", true, "redo"), ("Z", false, "redo"),
            ("c", false, "copy"),
            ("v", false, "paste"), ("v", true, "pasteAsPlainText"), ("V", false, "pasteAsPlainText"),
            ("x", false, "cut"),
            ("a", false, "selectAll")
        ])
    func editingShortcutsReachTheMatchingTextViewCommand(
        chars: String, hasShift: Bool, command: String
    ) throws {
        _ = manager.handleTextViewShortcut(
            chars: chars, hasShift: hasShift, on: textView, event: try passThroughEvent())

        #expect(textView.commands == [command])
    }

    /// The formatting arms land on the manager's own helpers rather than on the text view, so
    /// they are checked by what they did to the selection.
    @Test(
        arguments: [
            ("b", false, "bold"), ("i", false, "italic"),
            ("x", true, "strikethrough"), ("X", false, "strikethrough"),
            ("+", false, "larger"), ("=", false, "larger"), ("=", true, "larger"),
            ("-", false, "smaller")
        ])
    func formattingShortcutsApplyTheMatchingFormat(
        chars: String, hasShift: Bool, format: String
    ) throws {
        textView.setSelectedRange(NSRange(location: 0, length: 4))  // "Test"

        _ = manager.handleTextViewShortcut(
            chars: chars, hasShift: hasShift, on: textView, event: try passThroughEvent())

        let traits = NSFontManager.shared.traits(of: try selectionFont())
        switch format {
        case "bold":
            #expect(traits.contains(.boldFontMask))
        case "italic":
            #expect(traits.contains(.italicFontMask))
        case "strikethrough":
            #expect(try selectionStrikethrough() == NSUnderlineStyle.single.rawValue)
            #expect(
                textView.commands.isEmpty,
                "⌘⇧X strikes through; cutting here would destroy the selection instead")
        case "larger":
            #expect(try selectionFont().pointSize == 16)  // the fixture starts at 14
        case "smaller":
            #expect(try selectionFont().pointSize == 12)
        default:
            Issue.record("Unhandled expected format \"\(format)\"")
        }
    }

    // MARK: - Font formatting

    @Test(arguments: [NSFontTraitMask.boldFontMask, .italicFontMask])
    func toggleFontTraitAppliesTheTraitToTheSelection(trait: NSFontTraitMask) throws {
        textView.setSelectedRange(NSRange(location: 0, length: 4))  // "Test"

        manager.toggleFontTrait(trait, on: textView)

        #expect(NSFontManager.shared.traits(of: try selectionFont()).contains(trait))
    }

    @Test(arguments: [(true, CGFloat(16)), (false, CGFloat(12))])
    func changeFontSizeStepsTheSelectionByTwoPoints(increase: Bool, expected: CGFloat) throws {
        textView.setSelectedRange(NSRange(location: 0, length: 4))

        manager.changeFontSize(increase: increase, on: textView)

        #expect(try selectionFont().pointSize == expected)  // the fixture starts at 14
    }

    /// `max(8, pointSize - 2)` is the one boundary in the file: shrinking stops at 8pt and
    /// stays there rather than marching down to an unreadable size.
    @Test func decreasingFontSizeStopsAtEightPoints() throws {
        let range = NSRange(location: 0, length: 4)
        let storage = try #require(textView.textStorage, "Missing text storage")
        storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 10), range: range)
        textView.setSelectedRange(range)

        manager.changeFontSize(increase: false, on: textView)
        #expect(try selectionFont().pointSize == 8)

        manager.changeFontSize(increase: false, on: textView)
        #expect(try selectionFont().pointSize == 8, "The floor holds on a repeated decrease")
    }

    /// With nothing selected the change lands on the typing attributes, so the next thing typed
    /// comes out at the new size.
    @Test func changingSizeWithoutSelectionUpdatesTypingAttributes() {
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.typingAttributes[.font] = NSFont.systemFont(ofSize: 14)

        manager.changeFontSize(increase: true, on: textView)

        #expect((textView.typingAttributes[.font] as? NSFont)?.pointSize == 16)
    }

    /// Typing attributes that carry no font at all fall back to the app's default size rather
    /// than leaving the shortcut inert.
    @Test func changingSizeWithNoTypingFontStartsFromTheDefaultSize() throws {
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.typingAttributes = [:]
        try #require(
            textView.typingAttributes[.font] == nil,
            "The fallback is only under test while the typing attributes carry no font")

        manager.changeFontSize(increase: true, on: textView)

        #expect(
            (textView.typingAttributes[.font] as? NSFont)?.pointSize
                == AppConstants.Layout.defaultFontSize + 2)
    }

    /// The undo hook `applyFontChange` registers, driven through a real undo manager — which an
    /// `NSTextView` only has once it is in a window.
    @Test func formattingIsUndoable() throws {
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        editor.string = "Test Text"
        editor.textStorage?.addAttribute(
            .font, value: NSFont.systemFont(ofSize: 14), range: NSRange(location: 0, length: 9))

        // `isReleasedWhenClosed` off before anything else: AppKit's default of releasing the
        // window on close over-releases it under ARC and takes the test process down with it.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: .borderless,
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }

        window.contentView?.addSubview(editor)
        editor.allowsUndo = true
        editor.setSelectedRange(NSRange(location: 0, length: 4))  // "Test"

        manager.toggleFontTrait(.boldFontMask, on: editor)

        let storage = try #require(editor.textStorage, "Missing text storage")
        let bold = try #require(
            storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont, "Missing font")
        #expect(NSFontManager.shared.traits(of: bold).contains(.boldFontMask))

        editor.undoManager?.undo()

        let restored = try #require(
            storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont,
            "Missing font attribute after undo")
        #expect(NSFontManager.shared.traits(of: restored).contains(.boldFontMask) == false)
    }

    // MARK: - Strikethrough

    @Test func strikethroughTogglesTheSelectionBothWays() throws {
        textView.setSelectedRange(NSRange(location: 0, length: 4))  // "Test"

        manager.toggleStrikethrough(on: textView)
        #expect(try selectionStrikethrough() == NSUnderlineStyle.single.rawValue)

        manager.toggleStrikethrough(on: textView)
        #expect(try selectionStrikethrough() == 0)
    }

    @Test func strikethroughWithoutSelectionUpdatesTypingAttributes() {
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        manager.toggleStrikethrough(on: textView)
        #expect(
            (textView.typingAttributes[.strikethroughStyle] as? Int)
                == NSUnderlineStyle.single.rawValue)

        manager.toggleStrikethrough(on: textView)
        #expect((textView.typingAttributes[.strikethroughStyle] as? Int) == 0)
    }

    // MARK: - Note switching

    @Test(arguments: [(1, 0), (3, 2), (AppConstants.noteCount, AppConstants.noteCount - 1)])
    func selectNoteWritesTheZeroBasedIndexForAValidDigit(digit: Int, stored: Int) {
        #expect(manager.selectNote(noteIndex: digit))
        #expect(defaults.integer(forKey: AppConstants.selectedNoteIndexKey) == stored)
    }

    /// `noteCount + 1` is the first digit past the range — the value a `<=`/`<` slip would let
    /// through, which a test using 9 jumps clean over.
    @Test(arguments: [AppConstants.noteCount + 1, 9, -1])
    func selectNoteIgnoresOutOfRangeDigits(digit: Int) {
        // Digits past the note count aren't handled, so the key event passes through.
        #expect(manager.selectNote(noteIndex: digit) == false)
        #expect(
            defaults.object(forKey: AppConstants.selectedNoteIndexKey) == nil,
            "An unhandled digit must leave the selection alone")
    }

    /// ⌘0 jumps to the first empty note by id, not by whatever order the store hands them back.
    @Test func zeroSelectsTheFirstEmptyNoteById() throws {
        let context = try inMemoryContext()
        // Inserted out of order, and the two empty notes are not adjacent, so the `sortBy: \.id`
        // in the fetch is what decides the answer.
        for id in [4, 0, 6, 3, 1, 5, 2] {
            context.insert(NoteItem(id: id, rtfData: [3, 5].contains(id) ? Data() : Data([1])))
        }
        let shortcutManager = EditorShortcutManager(defaults: defaults, modelContext: context)

        #expect(shortcutManager.selectNote(noteIndex: 0))
        #expect(defaults.integer(forKey: AppConstants.selectedNoteIndexKey) == 3)
    }

    /// With every note full there is nothing to switch to, but ⌘0 is still ours: consuming it
    /// is what stops the digit reaching the text view.
    @Test func zeroConsumesTheKeyEvenWhenNoNoteIsEmpty() throws {
        let context = try inMemoryContext()
        for id in 0..<AppConstants.noteCount {
            context.insert(NoteItem(id: id, rtfData: Data([1])))
        }
        defaults.set(4, forKey: AppConstants.selectedNoteIndexKey)
        let shortcutManager = EditorShortcutManager(defaults: defaults, modelContext: context)

        #expect(shortcutManager.selectNote(noteIndex: 0))
        #expect(
            defaults.integer(forKey: AppConstants.selectedNoteIndexKey) == 4,
            "Nothing to select leaves the current note selected")
    }

    // MARK: - App-wide shortcuts
    //
    // ⌘Q and ⌘W are left uncovered on purpose: `handleAppShortcut` runs them rather than
    // reporting them, and `NSApp.terminate(nil)` would take the test process with it while
    // `NSApp.keyWindow?.performClose(nil)` would close whichever window another suite happens
    // to have made key.

    @Test func pinShortcutPostsTheTogglePinNotification() async {
        let center = NotificationCenter()
        let shortcutManager = EditorShortcutManager(notificationCenter: center, defaults: defaults)

        // The post is synchronous, so there is nothing to wait for once the call returns.
        await confirmation(".toggleWindowPin is posted") { posted in
            let observer = center.addObserver(
                forName: .toggleWindowPin, object: nil, queue: nil
            ) { _ in posted() }
            defer { center.removeObserver(observer) }

            #expect(
                shortcutManager.handleAppShortcut(chars: "p", hasShift: false),
                "⌘P is handled here, so the key event must be consumed")
        }
    }

    /// Digits route through `selectNote`; a shifted digit is not a note switch, and neither is
    /// ⌘⇧P — both have to fall through to the text-view shortcuts.
    @Test(
        arguments: [
            ("3", false, true), ("3", true, false),
            ("\(AppConstants.noteCount + 1)", false, false),
            ("p", true, false), ("k", false, false)
        ])
    func handleAppShortcutConsumesOnlyItsOwnKeys(chars: String, hasShift: Bool, isConsumed: Bool) {
        #expect(manager.handleAppShortcut(chars: chars, hasShift: hasShift) == isConsumed)
    }
}
