import AppKit
import SwiftData
import Testing

@testable import Heptad

/// `NSTextView` and friends are main-actor types, and the suite drives them directly.
@MainActor
struct EditorShortcutManagerTests {
    private let scratchDefaults: ScratchDefaults

    /// Private, because `changeFontSize` posts `.editorFontSizeDidChange`: on `.default` that would
    /// reach every other suite's coordinators and repaint their cached views.
    private let notificationCenter = NotificationCenter()
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
        textView.load(markdown: "Test Text")

        manager = EditorShortcutManager(
            notificationCenter: notificationCenter, defaults: scratchDefaults.defaults)
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

    /// Which characters of the buffer carry `emphasis` — see `NSAttributedString.carrying(_:)`.
    private func carrying(_ emphasis: Emphasis) throws -> String {
        try #require(textView.textStorage, "Missing text storage").carrying(emphasis)
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
            ("b", true), ("i", true), ("a", true),
            ("k", false), ("k", true)
        ])
    func dispatchTablePassesThroughUnclaimedKeys(chars: String, hasShift: Bool) throws {
        textView.setSelectedRange(NSRange(location: 0, length: 4))  // "Test"

        let result = manager.handleTextViewShortcut(
            chars: chars, hasShift: hasShift, on: textView, event: try passThroughEvent())

        #expect(result != nil, "An unclaimed key must be handed back, not consumed")
    }

    /// Every `chars` here is lowercase because that is all the table can be handed:
    /// `KeyboardLayout.commandKey` folds case, so shift is reported once, by `hasShift`.
    @Test(
        arguments: [
            ("z", false, "undo"), ("z", true, "redo"),
            ("c", false, "copy"),
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
    /// they are checked by what they did — to the note for the emphasis commands, and to the
    /// stored zoom for ⌘+/⌘-, which stopped being a text edit when notes became markdown.
    ///
    /// Which trait landed, and nothing about how the note spells it — that is
    /// `EditorFormattingTests`. The trait on the buffer is the cheapest witness that the key
    /// reached this command rather than merely reaching one.
    @Test(
        arguments: [
            ("b", false, Emphasis.strong), ("i", false, .emphasis),
            ("x", true, .strikethrough)
        ])
    func emphasisShortcutsFormatTheSelection(
        chars: String, hasShift: Bool, emphasis: Emphasis
    ) throws {
        textView.setSelectedRange(NSRange(location: 0, length: 4))  // "Test"

        let result = manager.handleTextViewShortcut(
            chars: chars, hasShift: hasShift, on: textView, event: try passThroughEvent())

        #expect(result == nil, "A format that applied means the key was consumed")
        #expect(textView.string == "Test Text", "and put no delimiters on screen")
        #expect(try carrying(emphasis) == "####.....", "the selection got this trait")
        #expect(
            textView.commands.isEmpty,
            "⌘⇧X strikes through; cutting here would destroy the selection instead")
    }

    /// The exact ±2pt step, and the floor and ceiling either side of it, are
    /// `EditorFormattingTests`' to pin; here it is enough that the key moved the zoom the right
    /// way and left the note's text alone.
    @Test(
        arguments: [
            ("+", false, true), ("=", false, true), ("=", true, true), ("-", false, false)
        ])
    func zoomShortcutsStepTheEditorFontSize(chars: String, hasShift: Bool, larger: Bool) throws {
        textView.setSelectedRange(NSRange(location: 0, length: 4))
        let before = EditorFontSize.current(defaults)

        let result = manager.handleTextViewShortcut(
            chars: chars, hasShift: hasShift, on: textView, event: try passThroughEvent())

        #expect(result == nil, "A zoom that applied means the key was consumed")
        let after = EditorFontSize.current(defaults)
        #expect(larger ? after > before : after < before)
        #expect(textView.string == "Test Text", "The zoom is a view setting, not an edit")
    }

    // MARK: - Paste
    //
    // Neither paste is a straight call into `NSTextView` any more. ⌘V used to be `paste(_:)`,
    // which inserted the clipboard's own attributes and was the direct cause of #117; it now
    // converts them to markdown. ⌘⇧V reads the clipboard itself because `pasteAsPlainText` reads
    // a single flavor and inserted nothing on a clipboard carrying only HTML, RTFD or a URL
    // (#114). Both are checked by what lands in the note. Which flavors resolve to what text is
    // `PlainTextPasteboardTests`' to pin; these cover the wiring and the empty case.

    /// HTML with no plain-text flavor. ⌘V keeps the bold, ⌘⇧V drops it — which is the only
    /// difference left between the two, and the reason both shortcuts still exist. Read back as
    /// markdown, since that is where the delimiters live now.
    @Test(
        arguments: [
            ("v", false, "**formatted**"),
            ("v", true, "formatted")
        ])
    func pasteShortcutsInsertTheClipboardAsTextOrMarkdown(
        chars: String, hasShift: Bool, expected: String
    ) throws {
        let scratch = ScratchPasteboard()
        scratch.write { $0.setData(Data("<b>formatted</b>".utf8), forType: .html) }
        let shortcutManager = EditorShortcutManager(
            defaults: defaults, pasteboard: scratch.pasteboard)
        textView.setSelectedRange(NSRange(location: 0, length: 9))  // all of "Test Text"

        let result = shortcutManager.handleTextViewShortcut(
            chars: chars, hasShift: hasShift, on: textView, event: try passThroughEvent())

        #expect(result == nil, "A paste that ran means the key was consumed")
        #expect(
            try carrying(.strong) == (expected.hasPrefix("**") ? "#########" : "........."),
            "⌘V brings the bold in as bold; ⌘⇧V brings none in at all")
        #expect(textView.markdown == expected)
        #expect(textView.commands.isEmpty, "Neither paste reaches NSTextView.paste any more")
    }

    /// A paste may bring in only what this app can write back out — the invariant #117 turns on.
    /// The bold has a markdown spelling and survives; the clipboard's colour and size do not and
    /// are taken back off. Checked on ⌘V, the one that reads the clipboard's formatting at all.
    @Test(.bug(id: 117))
    func pastingRichTextLeavesNoAttributesInTheNote() throws {
        let scratch = ScratchPasteboard()
        let styled = NSAttributedString(
            string: "formatted",
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: 24),
                .foregroundColor: NSColor.systemRed
            ])
        scratch.write {
            $0.setData(
                styled.rtf(from: NSRange(location: 0, length: styled.length)) ?? Data(),
                forType: .rtf)
        }
        let shortcutManager = EditorShortcutManager(
            defaults: defaults, pasteboard: scratch.pasteboard)
        textView.setSelectedRange(NSRange(location: 0, length: 9))

        let result = shortcutManager.handleTextViewShortcut(
            chars: "v", hasShift: false, on: textView, event: try passThroughEvent())

        #expect(result == nil, "A paste that ran means the key was consumed")
        #expect(textView.string == "formatted")
        #expect(textView.markdown == "**formatted**", "The bold arrives, and the note stores it")

        let storage = try #require(textView.textStorage)
        let font = try #require(storage.attribute(.font, at: 2, effectiveRange: nil) as? NSFont)
        #expect(font.pointSize == AppConstants.Layout.defaultFontSize, "at the note's own size")
        // The exact colour, not `!= .systemRed`: ⌘V goes clipboard → markdown → `String` →
        // `insertText`, so no attribute survives the trip and the negation would hold of every
        // possible outcome.
        #expect(
            storage.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor
                == .adaptiveEditorText,
            "in the note's own colour, which is the only kind that reaches a run")
    }

    /// An image is not text, and the note is left alone. The key is still consumed — handing it
    /// back would only find nothing else to run it and beep. Same rule as ⌘B in a plain note.
    @Test(arguments: [("v", false), ("v", true)])
    func pasteConsumesTheKeyWithNothingToPaste(chars: String, hasShift: Bool) throws {
        let scratch = ScratchPasteboard()
        try scratch.writeAnImage()
        let shortcutManager = EditorShortcutManager(
            defaults: defaults, pasteboard: scratch.pasteboard)

        let result = shortcutManager.handleTextViewShortcut(
            chars: chars, hasShift: hasShift, on: textView, event: try passThroughEvent())

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
            context.insert(NoteItem(id: id, text: [3, 5].contains(id) ? "" : "written in"))
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
            context.insert(NoteItem(id: id, text: "written in"))
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
