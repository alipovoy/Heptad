import Cocoa
import SwiftData
import SwiftUI

/// Manages editor-specific keyboard shortcuts (formatting, font size, note switching) via a
/// local event monitor, intercepting events before they reach the standard menu or text views.
///
/// A populated NSApp.mainMenu would intercept these key equivalents via performKeyEquivalent
/// before they reach NSTextView's keyDown key bindings — and in this accessory-mode app,
/// SwiftUI's Settings scene resets any manually-installed mainMenu once it becomes active
/// anyway, so a real menu isn't a reliable substitute yet. This monitor is the single source
/// of truth for shortcuts until the app can show a Dock icon and a real, SwiftUI-owned menu.
class EditorShortcutManager {
    private var localKeyMonitor: EventMonitor?
    private let notificationCenter: NotificationCenter
    private let defaults: UserDefaults

    /// The context ⌘0 searches for an empty note. Resolved on use rather than stored, so
    /// constructing the manager is never what opens the on-disk store — the app deliberately
    /// does that once, during launch, and a test that never presses ⌘0 never opens one at all.
    private let modelContext: @MainActor () -> ModelContext

    init(
        notificationCenter: NotificationCenter = .default,
        defaults: UserDefaults = .standard,
        modelContext: @autoclosure @escaping @MainActor () -> ModelContext
            = HeptadApp.sharedModelContainer.mainContext
    ) {
        self.notificationCenter = notificationCenter
        self.defaults = defaults
        self.modelContext = modelContext
        setupMonitor()
    }

    /// Starts the shortcut interceptor.
    func start() {
        localKeyMonitor?.start()
    }

    /// Stops the shortcut interceptor.
    func stop() {
        localKeyMonitor?.stop()
    }

    private func setupMonitor() {
        localKeyMonitor = EventMonitor(local: true, mask: .keyDown) { [weak self] event in
            guard let self = self else { return event }

            // Only handle ⌘ without option/control
            guard event.modifierFlags.contains(.command),
                !event.modifierFlags.contains(.option),
                !event.modifierFlags.contains(.control)
            else {
                return event
            }

            let chars = event.charactersIgnoringModifiers ?? ""
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

    /// Applies the ⌘ shortcuts that aren't scoped to the text view, so they work no matter what
    /// holds first responder. Returns true when the shortcut was handled and the key event
    /// should be consumed.
    func handleAppShortcut(chars: String, hasShift: Bool) -> Bool {
        if chars == "q" && !hasShift {
            NSApp.terminate(nil)
            return true
        }

        if chars == "w" && !hasShift {
            NSApp.keyWindow?.performClose(nil)
            return true
        }

        // ⌘P pins/unpins the window. WindowManager owns the state and observes this;
        // the shortcut manager stays free of any window dependency.
        if chars == "p" && !hasShift {
            notificationCenter.post(name: .toggleWindowPin, object: nil)
            return true
        }

        // Consume the event only when the digit maps to a real note (⌘0–⌘7);
        // out-of-range digits fall through so they aren't silently swallowed.
        if !hasShift, let noteIndex = Int(chars), selectNote(noteIndex: noteIndex) {
            return true
        }

        return false
    }

    /// Applies the text-view-scoped ⌘ shortcuts. Returns nil when the shortcut was
    /// handled and the event should be consumed, or the event itself to pass it through.
    func handleTextViewShortcut(
        chars: String, hasShift: Bool, on textView: NSTextView, event: NSEvent
    ) -> NSEvent? {
        switch chars {
        case "b" where !hasShift:
            toggleFontTrait(.boldFontMask, on: textView)
            return nil  // consumed
        case "i" where !hasShift:
            toggleFontTrait(.italicFontMask, on: textView)
            return nil
        case "+", "=":
            // ⌘+ on US keyboard is ⌘⇧=, so we accept shift here
            changeFontSize(increase: true, on: textView)
            return nil
        case "-":
            changeFontSize(increase: false, on: textView)
            return nil
        case "z" where !hasShift:
            textView.undoManager?.undo()
            return nil
        case "z" where hasShift, "Z":
            textView.undoManager?.redo()
            return nil
        case "c" where !hasShift:
            textView.copy(nil)
            return nil
        case "v" where !hasShift:
            textView.paste(nil)
            return nil
        case "v" where hasShift, "V":
            textView.pasteAsPlainText(nil)
            return nil
        case "x" where !hasShift:
            textView.cut(nil)
            return nil
        case "x" where hasShift, "X":
            toggleStrikethrough(on: textView)
            return nil
        case "a" where !hasShift:
            textView.selectAll(nil)
            return nil
        default:
            return event  // pass through
        }
    }

    // MARK: - Note Switching

    /// ⌘1–⌘7 select a note directly; ⌘0 selects the first empty one.
    /// Returns true when the index maps to a note-switch action, so the caller
    /// only consumes the key event for digits the app actually handles.
    @discardableResult
    func selectNote(noteIndex: Int) -> Bool {
        if noteIndex == 0 {
            // The context stays put and only the note's id comes back out: a ModelContext is
            // explicitly not Sendable, so it can't cross out of the actor it belongs to. The
            // assumption itself is sound — the local key monitor that gets here, and the
            // shared container's mainContext, are both the main thread's.
            let firstEmptyId = MainActor.assumeIsolated { () -> Int? in
                let descriptor = FetchDescriptor<NoteItem>(sortBy: [SortDescriptor(\.id)])
                guard let notes = try? modelContext().fetch(descriptor) else { return nil }
                return notes.first(where: { $0.isEmpty })?.id
            }

            // ⌘0 is handled either way: with every note full there is nothing to switch to,
            // but the key still belongs to us and must not fall through to the text view.
            if let firstEmptyId {
                defaults.set(firstEmptyId, forKey: AppConstants.selectedNoteIndexKey)
            }
            return true
        } else if (1...AppConstants.noteCount).contains(noteIndex) {
            defaults.set(noteIndex - 1, forKey: AppConstants.selectedNoteIndexKey)
            return true
        }
        return false
    }

    // MARK: - Font Formatting

    func toggleFontTrait(_ trait: NSFontTraitMask, on textView: NSTextView) {
        let fontManager = NSFontManager.shared
        applyFontChange(to: textView, actionName: "Formatting") { font in
            fontManager.traits(of: font).contains(trait)
                ? fontManager.convert(font, toNotHaveTrait: trait)
                : fontManager.convert(font, toHaveTrait: trait)
        }
    }

    /// Steps the selection by two points, stopping at the bound in the direction of travel.
    ///
    /// The outer `max`/`min` are what keep a bound from *dragging* a run back to itself. The
    /// editor is rich text with paste wired up, so a run pasted from another app can arrive well
    /// past either bound — and ⌘+ on a 90pt heading pulling it down to 72 would mean ⌘+ and ⌘-
    /// did the same thing to it. A run already outside the range is left where it is.
    func changeFontSize(increase: Bool, on textView: NSTextView) {
        applyFontChange(to: textView, actionName: "Font Size") { font in
            let size = font.pointSize
            let newSize =
                increase
                ? max(size, min(size + 2, AppConstants.Layout.maxFontSize))
                : min(size, max(size - 2, AppConstants.Layout.minFontSize))
            return NSFontManager.shared.convert(font, toSize: newSize)
        }
    }

    /// Applies a font transform to the selection (undoably, via the text view's
    /// standard should/didChangeText hooks) or to the typing attributes when empty.
    private func applyFontChange(
        to textView: NSTextView, actionName: String, transform: (NSFont) -> NSFont
    ) {
        let range = textView.selectedRange()

        if range.length > 0 {
            guard let textStorage = textView.textStorage,
                textView.shouldChangeText(in: range, replacementString: nil)
            else { return }

            textStorage.beginEditing()
            textStorage.enumerateAttribute(.font, in: range, options: []) { value, attrRange, _ in
                guard let oldFont = value as? NSFont else { return }
                textStorage.addAttribute(.font, value: transform(oldFont), range: attrRange)
            }
            textStorage.endEditing()
            textView.didChangeText()
            textView.undoManager?.setActionName(actionName)
        } else {
            var attrs = textView.typingAttributes
            let currentFont =
                attrs[.font] as? NSFont
                ?? NSFont.systemFont(ofSize: AppConstants.Layout.defaultFontSize)
            attrs[.font] = transform(currentFont)
            textView.typingAttributes = attrs
        }
    }

    // MARK: - Strikethrough

    /// Flips strikethrough on the selection, run by run.
    ///
    /// Per-run rather than reading the first character and painting that one answer over the
    /// whole selection: on a selection that is half struck through, flattening loses the state
    /// of every run after the first, and — the reason this matters beyond taste — it made ⌘⇧X
    /// behave differently from ⌘B and ⌘I, which have always transformed each run on its own
    /// terms via `applyFontChange`. Both commands now follow the same rule.
    func toggleStrikethrough(on textView: NSTextView) {
        let range = textView.selectedRange()
        let key = NSAttributedString.Key.strikethroughStyle

        if range.length > 0 {
            guard let textStorage = textView.textStorage,
                textView.shouldChangeText(in: range, replacementString: nil)
            else { return }

            textStorage.beginEditing()
            // Runs with no strikethrough attribute at all arrive here with a nil value, which
            // is the unstruck case and gets struck like any other.
            textStorage.enumerateAttribute(key, in: range, options: []) { value, attrRange, _ in
                let isStruck = (value as? Int ?? 0) != 0
                textStorage.addAttribute(
                    key, value: isStruck ? 0 : NSUnderlineStyle.single.rawValue, range: attrRange)
            }
            textStorage.endEditing()
            textView.didChangeText()
            textView.undoManager?.setActionName("Formatting")
        } else {
            var attrs = textView.typingAttributes
            let hasStrikethrough = (attrs[key] as? Int ?? 0) != 0
            attrs[key] = hasStrikethrough ? 0 : NSUnderlineStyle.single.rawValue
            textView.typingAttributes = attrs
        }
    }
}
