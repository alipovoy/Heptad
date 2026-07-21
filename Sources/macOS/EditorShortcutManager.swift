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

    init() {
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

            if chars == "q" && !hasShift {
                NSApp.terminate(nil)
                return nil
            }

            if chars == "w" && !hasShift {
                NSApp.keyWindow?.performClose(nil)
                return nil
            }

            // Consume the event only when the digit maps to a real note (⌘0–⌘7);
            // out-of-range digits fall through so they aren't silently swallowed.
            if !hasShift, let noteIndex = Int(chars), self.selectNote(noteIndex: noteIndex) {
                return nil
            }

            // Find the NSTextView first responder
            guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else {
                return event
            }

            switch chars {
            case "b" where !hasShift:
                self.toggleFontTrait(.boldFontMask, on: textView)
                return nil  // consumed
            case "i" where !hasShift:
                self.toggleFontTrait(.italicFontMask, on: textView)
                return nil
            case "+", "=":
                // ⌘+ on US keyboard is ⌘⇧=, so we accept shift here
                self.changeFontSize(increase: true, on: textView)
                return nil
            case "-":
                self.changeFontSize(increase: false, on: textView)
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
                self.toggleStrikethrough(on: textView)
                return nil
            case "a" where !hasShift:
                textView.selectAll(nil)
                return nil
            default:
                return event  // pass through
            }
        }
    }

    // MARK: - Note Switching

    /// ⌘1–⌘7 select a note directly; ⌘0 selects the first empty one.
    /// Returns true when the index maps to a note-switch action, so the caller
    /// only consumes the key event for digits the app actually handles.
    @discardableResult
    func selectNote(noteIndex: Int) -> Bool {
        if noteIndex == 0 {
            MainActor.assumeIsolated {
                let context = HeptadApp.sharedModelContainer.mainContext
                let descriptor = FetchDescriptor<NoteItem>(sortBy: [SortDescriptor(\.id)])
                guard let notes = try? context.fetch(descriptor),
                    let firstEmpty = notes.first(where: { $0.isEmpty })
                else { return }
                UserDefaults.standard.set(firstEmpty.id, forKey: AppConstants.selectedNoteIndexKey)
            }
            return true
        } else if (1...AppConstants.noteCount).contains(noteIndex) {
            UserDefaults.standard.set(noteIndex - 1, forKey: AppConstants.selectedNoteIndexKey)
            return true
        }
        return false
    }

    // MARK: - Font Formatting

    func toggleFontTrait(_ trait: NSFontTraitMask, on textView: NSTextView) {
        let fm = NSFontManager.shared
        applyFontChange(to: textView, actionName: "Formatting") { font in
            fm.traits(of: font).contains(trait)
                ? fm.convert(font, toNotHaveTrait: trait)
                : fm.convert(font, toHaveTrait: trait)
        }
    }

    func changeFontSize(increase: Bool, on textView: NSTextView) {
        applyFontChange(to: textView, actionName: "Font Size") { font in
            let newSize = increase ? font.pointSize + 2 : max(8, font.pointSize - 2)
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
                ?? NSFont.systemFont(ofSize: AppConstants.UI.defaultFontSize)
            attrs[.font] = transform(currentFont)
            textView.typingAttributes = attrs
        }
    }

    // MARK: - Strikethrough

    func toggleStrikethrough(on textView: NSTextView) {
        let range = textView.selectedRange()
        let key = NSAttributedString.Key.strikethroughStyle

        if range.length > 0 {
            guard let textStorage = textView.textStorage,
                textView.shouldChangeText(in: range, replacementString: nil)
            else { return }

            let hasStrikethrough =
                (textStorage.attribute(key, at: range.location, effectiveRange: nil) as? Int ?? 0)
                != 0
            let newValue = hasStrikethrough ? 0 : NSUnderlineStyle.single.rawValue

            textStorage.beginEditing()
            textStorage.addAttribute(key, value: newValue, range: range)
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
