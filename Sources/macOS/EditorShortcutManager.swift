import Cocoa
import SwiftData

/// Manages editor-specific keyboard shortcuts (formatting, font size, note switching) via a
/// local event monitor, intercepting events before they reach the standard menu or text views.
///
/// A populated NSApp.mainMenu would intercept these key equivalents via performKeyEquivalent
/// before they reach NSTextView's keyDown key bindings — and in this accessory-mode app,
/// SwiftUI's Settings scene resets any manually-installed mainMenu once it becomes active
/// anyway, so a real menu isn't a reliable substitute yet. This monitor is the single source
/// of truth for shortcuts until the app can show a Dock icon and a real, SwiftUI-owned menu.
@MainActor
class EditorShortcutManager {
    private var localKeyMonitor: EventMonitor?
    private let notificationCenter: NotificationCenter
    private let defaults: UserDefaults

    /// Where ⌘⇧V reads from. Injected for the same reason as everything else here: a test that
    /// drove the real clipboard would trample whatever the person running it had copied.
    private let pasteboard: NSPasteboard

    /// Quit and close-window, behind a protocol so the tests can assert the decision without
    /// performing it. See `AppCommanding`.
    private let appCommands: AppCommanding

    /// The context ⌘0 searches for an empty note. Resolved on use rather than stored, so
    /// constructing the manager is never what opens the on-disk store — the app deliberately
    /// does that once, during launch, and a test that never presses ⌘0 never opens one at all.
    ///
    /// `@MainActor` on the closure, not just on the class: a default argument is evaluated in
    /// the caller's context rather than the callee's, and the container it reaches for is
    /// main-actor isolated.
    private let modelContext: @MainActor () -> ModelContext

    init(
        notificationCenter: NotificationCenter = .default,
        defaults: UserDefaults = .standard,
        appCommands: AppCommanding = SystemAppCommander(),
        pasteboard: NSPasteboard = .general,
        modelContext: @autoclosure @escaping @MainActor () -> ModelContext
            = HeptadApp.sharedModelContainer.mainContext
    ) {
        self.notificationCenter = notificationCenter
        self.defaults = defaults
        self.appCommands = appCommands
        self.pasteboard = pasteboard
        self.modelContext = modelContext
        setupMonitor()
    }

    /// Starts the shortcut interceptor. No matching stop: it goes away with the process.
    func start() {
        localKeyMonitor?.start()
    }

    private func setupMonitor() {
        localKeyMonitor = EventMonitor(local: true, mask: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            guard Self.handlesModifiers(event.modifierFlags) else { return event }

            // Not `charactersIgnoringModifiers`: on a non-Latin layout every case below would
            // miss. See `KeyboardLayout`.
            let chars = KeyboardLayout.commandKey(for: event)
            let hasShift = event.modifierFlags.contains(.shift)

            if self.handleAppShortcut(chars: chars, hasShift: hasShift) {
                return nil
            }

            // Find the NSTextView first responder
            guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else {
                return event
            }

            return self.handleTextViewShortcut(
                chars: chars, hasShift: hasShift, on: textView, event: event)
        }
    }

    /// The gate both dispatch tables sit behind: ⌘ held, option and control not.
    ///
    /// The exclusions carry the weight. ⌥⌘B resolves to "b" just as ⌘B does, so without them the
    /// tables would claim every ⌥⌘ and ⌃⌘ combination the system and NSTextView own. Shift is left
    /// to the tables, which read it themselves.
    static func handlesModifiers(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.contains(.command)
            && !flags.contains(.option)
            && !flags.contains(.control)
    }

    /// Applies the ⌘ shortcuts that aren't scoped to the text view, so they work no matter what
    /// holds first responder. Returns true when the shortcut was handled and the key event
    /// should be consumed.
    func handleAppShortcut(chars: String, hasShift: Bool) -> Bool {
        switch chars {
        case "q" where !hasShift:
            appCommands.terminate()
        case "w" where !hasShift:
            appCommands.closeKeyWindow()
        // ⌘P pins/unpins the window. WindowManager owns the state and observes this;
        // the shortcut manager stays free of any window dependency.
        case "p" where !hasShift:
            notificationCenter.post(name: .toggleWindowPin, object: nil)
        default:
            // Consume the event only when the digit maps to a real note (⌘0–⌘7);
            // out-of-range digits fall through so they aren't silently swallowed.
            guard !hasShift, let noteIndex = Int(chars) else { return false }
            return selectNote(noteIndex: noteIndex)
        }
        return true
    }

    /// Applies the text-view-scoped ⌘ shortcuts. Returns nil when the shortcut was
    /// handled and the event should be consumed, or the event itself to pass it through.
    func handleTextViewShortcut(
        chars: String, hasShift: Bool, on textView: NSTextView, event: NSEvent
    ) -> NSEvent? {
        switch chars {
        case "b" where !hasShift:
            toggleEmphasis(.strong, on: textView)
            return nil  // consumed
        case "i" where !hasShift:
            toggleEmphasis(.emphasis, on: textView)
            return nil
        case "+", "=":
            // ⌘+ on US keyboard is ⌘⇧=, so we accept shift here
            changeFontSize(increase: true)
            return nil
        case "-":
            changeFontSize(increase: false)
            return nil
        case "z" where !hasShift:
            textView.undoManager?.undo()
            return nil
        case "z" where hasShift:
            textView.undoManager?.redo()
            return nil
        case "c" where !hasShift:
            textView.copy(nil)
            return nil
        case "v" where !hasShift:
            pasteAsMarkdown(on: textView)
            return nil
        case "v" where hasShift:
            pasteAsPlainText(on: textView)
            return nil
        case "x" where !hasShift:
            textView.cut(nil)
            return nil
        case "x" where hasShift:
            toggleStrikethrough(on: textView)
            return nil
        case "u" where hasShift:
            toggleCheckbox(on: textView)
            return nil
        case "a" where !hasShift:
            textView.selectAll(nil)
            return nil
        // ⌘⌫ is deliberately absent: the key belongs to `NSTextView`'s "delete to beginning of
        // line", and emptying a note is ⌘A ⌫.
        default:
            return event  // pass through
        }
    }

    // MARK: - Paste

    /// ⌘V. The clipboard's formatting is converted to markdown on the way in — bold, italic,
    /// strikethrough and links survive as source — and everything else is dropped.
    ///
    /// This replaces `NSTextView.paste`, which inserted the clipboard's own attributes and was
    /// the direct cause of #117: the run's colour and alignment landed in the storage *and* in
    /// `typingAttributes`, where no command could reach them and undo would not restore them.
    /// Nothing that arrives through here is unrepresentable, so nothing can be stranded.
    ///
    /// A plain-text note takes the characters and no markup, because that mode silences `⌘B`,
    /// `⌘I` and `⌘⇧X`: converting a pasted bold run to `**secret**` there would put delimiters
    /// in the note that none of its own commands could take back out — the very thing this is
    /// supposed to prevent.
    func pasteAsMarkdown(on textView: NSTextView) {
        guard isStyled(textView) else {
            insert(pasteboard.plainTextForPaste(), on: textView)
            return
        }

        insert(pasteboard.markdownForPaste(), on: textView, rendering: true)
    }

    /// ⌘⇧V, in place of `NSTextView.pasteAsPlainText` — which reads one flavor and gives up,
    /// leaving the shortcut a silent no-op on clipboards ⌘V pastes fine. See
    /// `plainTextForPaste` for which clipboards those are (#114).
    ///
    /// Still distinct from ⌘V now that both insert text: this one takes the clipboard's
    /// characters and no markup at all, for when the markdown a page's bold would produce is
    /// exactly what you do not want in the note.
    func pasteAsPlainText(on textView: NSTextView) {
        insert(pasteboard.plainTextForPaste(), on: textView)
    }

    /// The insertion both paste commands share.
    ///
    /// nil text means the clipboard holds nothing textual. The key stays consumed anyway, for
    /// the same reason ⌘B is consumed in a plain-text note: it is still the app's key, and
    /// handing it back would only find nothing else to run it and beep.
    /// `rendering` turns the markdown into what it describes on the way in, which is what ⌘V
    /// wants in a formatted note: the clipboard's bold arrives as bold, not as two asterisks in
    /// a buffer that holds none. ⌘⇧V leaves it off — plain means literal, `**` included.
    private func insert(_ text: String?, on textView: NSTextView, rendering: Bool = false) {
        guard let text else { return }

        // NSNotFound where the view will take no user edit at all, which is not a range that
        // can be pasted over.
        let range = textView.rangeForUserTextChange
        guard range.location != NSNotFound else { return }

        // `insertText` rather than a text-storage edit of our own: it is the path a keystroke
        // takes, so this lands as a single undo step without the method knowing that rule.
        if rendering, let markdownView = textView as? MarkdownTextView {
            textView.insertText(
                RichTextRendering.attributed(from: text, appearance: markdownView.styling),
                replacementRange: range)
        } else {
            textView.insertText(text, replacementRange: range)
        }

        textView.undoManager?.setActionName("Paste")
    }

    // MARK: - Note Switching

    /// ⌘1–⌘7 select a note directly; ⌘0 selects the first empty one.
    /// Returns true when the index maps to a note-switch action, so the caller
    /// only consumes the key event for digits the app actually handles.
    @discardableResult
    func selectNote(noteIndex: Int) -> Bool {
        if noteIndex == 0 {
            // A ModelContext is explicitly not Sendable and belongs to the main actor, which is
            // where this now runs — the class is isolated, so the assumption the local key
            // monitor used to state by hand is the compiler's to check.
            let descriptor = FetchDescriptor<NoteItem>(sortBy: [SortDescriptor(\.id)])
            let firstEmptyId = (try? modelContext().fetch(descriptor))?
                .first(where: { $0.isEmpty })?.id

            // ⌘0 is handled either way: with every note full there is nothing to switch to,
            // but the key still belongs to us and must not fall through to the text view.
            if let firstEmptyId {
                NoteSelection.store(firstEmptyId, in: defaults)
            }
            return true
        } else if (1...AppConstants.noteCount).contains(noteIndex) {
            NoteSelection.store(noteIndex - 1, in: defaults)
            return true
        }
        return false
    }

    // MARK: - Formatting

    /// ⌘B, ⌘I and ⌘⇧X, which turn a trait on over the selection or off again — see
    /// `AttributedFormatting`, and #124 for what they did before that.
    ///
    /// No-op in a plain-text note. That mode holds the source, where the only thing these could
    /// do is type delimiters the user is already free to type. The key stays consumed either way
    /// — it is still the app's.
    func toggleEmphasis(_ emphasis: Emphasis, on textView: NSTextView) {
        guard isStyled(textView), let markdownView = textView as? MarkdownTextView,
            let storage = textView.textStorage
        else { return }

        let selection = textView.selectedRange()

        // Through the change hooks, so the toggle lands on the per-note undo stack as one step.
        // An empty selection changes no characters and so registers nothing: it moves the caret's
        // typing attributes instead, and ⌘Z has nothing to put back.
        guard selection.length == 0
            || textView.shouldChangeText(in: selection, replacementString: nil)
        else { return }

        textView.typingAttributes = AttributedFormatting.toggle(
            emphasis, over: selection, in: storage, appearance: markdownView.styling)

        if selection.length > 0 {
            textView.didChangeText()
            textView.undoManager?.setActionName("Formatting")
        }
    }

    /// Steps the editor's zoom by two points, stopping at the bound in the direction of travel.
    ///
    /// One size for the whole app rather than per run: font size is the one thing the old
    /// attributed editor could do that has no markdown spelling, so it became a view setting
    /// when notes became text. See `EditorFontSize`.
    ///
    /// Deliberately not behind the plain-text guard the commands above carry: one uniform font
    /// is still a size the user may want to change. `PlainTextModeTests` names ⌘B, ⌘I and ⌘⇧X as
    /// the commands plain mode silences, and leaves this one out.
    ///
    /// Takes no text view. The zoom is an app-wide setting that every editor picks up through
    /// `.editorFontSizeDidChange`, so there is no view for this to act on.
    func changeFontSize(increase: Bool) {
        EditorFontSize.step(
            increase: increase, defaults: defaults, notificationCenter: notificationCenter)
    }

    /// Whether the view draws its markdown, which is what the formatting and paste commands need
    /// to know. Read off the view rather than the note: the shortcut manager finds a text view
    /// through the responder chain and never sees the model.
    ///
    /// A view that is not a `MarkdownTextView` is not one of this app's editors and gets the
    /// plain reading — `MacRichTextEditor` will not build any other kind.
    private func isStyled(_ textView: NSTextView) -> Bool {
        (textView as? MarkdownTextView)?.styling.isStyled ?? false
    }

    // MARK: - Checkboxes

    /// ⌘⇧U flips the checkbox on the line holding the insertion point, and does nothing on a
    /// line without one. Unlike the formatting commands this is a text edit, so it goes
    /// through the same should/didChangeText pair the list continuation uses.
    ///
    /// `caretFollowsMarkup: false` because the box is behind the caret, not under it: this flips
    /// `[ ]` at the head of the line and leaves the caret in whatever run it was already in.
    func toggleCheckbox(on textView: NSTextView) {
        guard let markdownView = textView as? MarkdownTextView,
            let edit = ListContinuation.checkboxEdit(
                in: textView.string as NSString, selectedRange: textView.selectedRange())
        else { return }

        markdownView.applyMarkup(edit, caretFollowsMarkup: false)
        textView.undoManager?.setActionName("Checkbox")
    }

    // MARK: - Strikethrough

    /// ⌘⇧X, the same path as ⌘B and ⌘I.
    func toggleStrikethrough(on textView: NSTextView) {
        toggleEmphasis(.strikethrough, on: textView)
    }
}
