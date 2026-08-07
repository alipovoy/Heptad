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
    override func selectAll(_ sender: Any?) { record("selectAll") }
}

/// Records the app-level actions ⌘Q and ⌘W ask for, instead of quitting the test process or
/// closing whichever window another suite left key.
@MainActor
private final class SpyAppCommander: AppCommanding {
    private(set) var performed: [String] = []

    nonisolated init() {}

    func terminate() { performed.append("terminate") }
    func closeKeyWindow() { performed.append("closeKeyWindow") }
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
    private let scratchDefaults: ScratchDefaults
    private let textView: SpyTextView
    private let manager: EditorShortcutManager

    /// Convenience for the many test bodies below that read or write the suite directly, e.g.
    /// `selectNote`'s written index.
    private var defaults: UserDefaults { scratchDefaults.defaults }

    init() throws {
        // A scratch suite rather than `.standard`: `selectNote` writes the selected note index,
        // and a killed test run would otherwise leave the real app pointing at another note.
        scratchDefaults = try ScratchDefaults(name: "EditorShortcutManagerTests")

        textView = SpyTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        textView.string = "Test Text"
        textView.textStorage?.addAttribute(
            .font, value: NSFont.systemFont(ofSize: 14), range: NSRange(location: 0, length: 9))

        manager = EditorShortcutManager(defaults: scratchDefaults.defaults)
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
    // The table is a flat `switch` over characters and shift. A consumed key either runs a
    // text-view command or applies a format — never both, never neither — so the two tests below
    // that check *what* ran also pin *that* something ran, through their own `result == nil`
    // assertion. That leaves only the keys the table declines to claim as this section's own
    // responsibility to pin: the shifted forms of the single-letter commands, which are not
    // shortcuts at all, and ⌘K/⌘⇧K, which nothing claims either way.

    /// The keys `handleTextViewShortcut` hands straight back rather than dispatching anywhere.
    @Test(
        arguments: [
            ("b", true), ("i", true), ("c", true), ("a", true),
            ("k", false), ("k", true)
        ])
    func dispatchTablePassesThroughUnclaimedKeys(chars: String, hasShift: Bool) throws {
        textView.setSelectedRange(NSRange(location: 0, length: 4))  // "Test"

        let result = manager.handleTextViewShortcut(
            chars: chars, hasShift: hasShift, on: textView, event: try passThroughEvent())

        #expect(result != nil, "An unclaimed key must be handed back, not consumed")
    }

    @Test(
        arguments: [
            ("z", false, "undo"), ("z", true, "redo"), ("Z", false, "redo"),
            ("c", false, "copy"),
            ("v", false, "paste"),
            ("x", false, "cut"),
            ("a", false, "selectAll")
        ])
    func editingShortcutsReachTheMatchingTextViewCommand(
        chars: String, hasShift: Bool, command: String
    ) throws {
        let result = manager.handleTextViewShortcut(
            chars: chars, hasShift: hasShift, on: textView, event: try passThroughEvent())

        #expect(textView.commands == [command])
        #expect(result == nil, "A command that ran means the key was consumed")
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

        let result = manager.handleTextViewShortcut(
            chars: chars, hasShift: hasShift, on: textView, event: try passThroughEvent())

        #expect(result == nil, "A format that applied means the key was consumed")
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
            // The exact +2pt step, and the floor/ceiling either side of it, are
            // `EditorFormattingTests`' to pin; here it is enough that this key grew the font.
            #expect(try selectionFont().pointSize > 14)  // the fixture starts at 14
        case "smaller":
            #expect(try selectionFont().pointSize < 14)
        default:
            Issue.record("Unhandled expected format \"\(format)\"")
        }
    }

    // MARK: - Clean paste
    //
    // ⌘⇧V is the one editing shortcut that is not a straight call into `NSTextView`: it reads the
    // clipboard itself, because `pasteAsPlainText` reads a single flavor and inserted nothing on a
    // clipboard that only carries HTML, RTFD or a URL (#114). So it is checked by what lands in
    // the note rather than by which command the spy saw. Which flavors resolve to what text is
    // `PlainTextPasteboardTests`' to pin; these two cover the wiring and the empty case.

    /// HTML with no plain-text flavor: the clipboard ⌘V pasted and ⌘⇧V did not. Bold is what
    /// separates the two — landing here still bold would mean the key reached `paste`.
    @Test(arguments: [("v", true), ("V", false)])
    func shiftVPastesRichClipboardTextWithoutItsFormatting(chars: String, hasShift: Bool) throws {
        let scratch = ScratchPasteboard()
        let html = Data("<b>formatted</b>".utf8)
        scratch.write { $0.setData(html, forType: .html) }
        let shortcutManager = EditorShortcutManager(
            defaults: defaults, pasteboard: scratch.pasteboard)
        textView.setSelectedRange(NSRange(location: 0, length: 9))  // all of "Test Text"

        let result = shortcutManager.handleTextViewShortcut(
            chars: chars, hasShift: hasShift, on: textView, event: try passThroughEvent())

        #expect(result == nil, "A paste that ran means the key was consumed")
        #expect(textView.string == "formatted")
        #expect(!NSFontManager.shared.traits(of: try selectionFont()).contains(.boldFontMask))
    }

    /// An image is not text, and the note is left alone. The key is still consumed — handing it
    /// back would only find nothing else to run it and beep. Same rule as ⌘B in a plain note.
    @Test func shiftVConsumesTheKeyWithNothingToPaste() throws {
        let scratch = ScratchPasteboard()
        try scratch.writeAnImage()
        let shortcutManager = EditorShortcutManager(
            defaults: defaults, pasteboard: scratch.pasteboard)

        let result = shortcutManager.handleTextViewShortcut(
            chars: "V", hasShift: false, on: textView, event: try passThroughEvent())

        #expect(result == nil)
        #expect(textView.string == "Test Text")
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

    /// ⌘Q and ⌘W reach the app commands, and the shifted forms reach nothing.
    ///
    /// Against the real `NSApp` neither could be asserted at all — `terminate(nil)` takes the
    /// test process with it, and `performClose` acts on whichever window another suite happened
    /// to make key. `SpyAppCommander` is what makes the decision observable without carrying
    /// it out; see `AppCommanding`.
    @Test(
        arguments: [
            ("q", false, ["terminate"]), ("q", true, []),
            ("w", false, ["closeKeyWindow"]), ("w", true, [])
        ])
    func quitAndCloseReachTheAppCommands(chars: String, hasShift: Bool, expected: [String]) {
        let commands = SpyAppCommander()
        let shortcutManager = EditorShortcutManager(defaults: defaults, appCommands: commands)

        let isConsumed = shortcutManager.handleAppShortcut(chars: chars, hasShift: hasShift)

        #expect(commands.performed == expected)
        // A key that reaches an app command is ours to consume; one that reaches none has to
        // fall through to the text view.
        #expect(isConsumed == !expected.isEmpty)
    }

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
