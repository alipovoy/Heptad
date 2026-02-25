import Cocoa
import SwiftUI

/// Manages editor-specific keyboard shortcuts like formatting (⌘B, ⌘I) and font size (⌘+, ⌘-).
/// Uses a local event monitor to intercept events before they reach the standard menu or text views,
/// ensuring native text view behaviors (like undo/redo/copy/paste) remain intact.
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
            case "x" where !hasShift:
                textView.cut(nil)
                return nil
            case "a" where !hasShift:
                textView.selectAll(nil)
                return nil
            case "w" where !hasShift:
                NSApp.keyWindow?.performClose(nil)
                return nil
            default:
                return event  // pass through
            }
        }
    }

    // MARK: - Font Formatting Helpers

    func toggleFontTrait(_ trait: NSFontTraitMask, on textView: NSTextView) {
        let fm = NSFontManager.shared
        let range = textView.selectedRange()

        if range.length > 0 {
            guard let textStorage = textView.textStorage else { return }
            let oldText = NSAttributedString(
                attributedString: textStorage.attributedSubstring(from: range))

            textStorage.beginEditing()
            textStorage.enumerateAttribute(.font, in: range, options: []) { value, attrRange, _ in
                guard let oldFont = value as? NSFont else { return }
                let traits = fm.traits(of: oldFont)
                let newFont: NSFont
                if traits.contains(trait) {
                    newFont = fm.convert(oldFont, toNotHaveTrait: trait)
                } else {
                    newFont = fm.convert(oldFont, toHaveTrait: trait)
                }
                textStorage.addAttribute(.font, value: newFont, range: attrRange)
            }
            textStorage.endEditing()
            textView.didChangeText()

            let newText = NSAttributedString(
                attributedString: textStorage.attributedSubstring(from: range))
            registerUndo(
                for: textView, range: range, oldText: oldText, newText: newText,
                actionName: "Formatting")
            if textView.undoManager?.isUndoing == false {
                textView.undoManager?.setActionName("Formatting")
            }
        } else {
            var attrs = textView.typingAttributes
            let currentFont =
                attrs[.font] as? NSFont
                ?? NSFont.systemFont(ofSize: AppConstants.UI.defaultFontSize)
            let traits = fm.traits(of: currentFont)
            let newFont: NSFont
            if traits.contains(trait) {
                newFont = fm.convert(currentFont, toNotHaveTrait: trait)
            } else {
                newFont = fm.convert(currentFont, toHaveTrait: trait)
            }
            attrs[.font] = newFont
            textView.typingAttributes = attrs
        }
    }

    func changeFontSize(increase: Bool, on textView: NSTextView) {
        let range = textView.selectedRange()

        if range.length > 0 {
            guard let textStorage = textView.textStorage else { return }
            let oldText = NSAttributedString(
                attributedString: textStorage.attributedSubstring(from: range))

            textStorage.beginEditing()
            textStorage.enumerateAttribute(.font, in: range, options: []) { value, attrRange, _ in
                guard let oldFont = value as? NSFont else { return }
                let newSize = increase ? oldFont.pointSize + 2 : max(8, oldFont.pointSize - 2)
                let newFont = NSFontManager.shared.convert(oldFont, toSize: newSize)
                textStorage.addAttribute(.font, value: newFont, range: attrRange)
            }
            textStorage.endEditing()
            textView.didChangeText()

            let newText = NSAttributedString(
                attributedString: textStorage.attributedSubstring(from: range))
            registerUndo(
                for: textView, range: range, oldText: oldText, newText: newText,
                actionName: "Font Size")
            if textView.undoManager?.isUndoing == false {
                textView.undoManager?.setActionName("Font Size")
            }
        } else {
            var attrs = textView.typingAttributes
            let currentFont =
                attrs[.font] as? NSFont
                ?? NSFont.systemFont(ofSize: AppConstants.UI.defaultFontSize)
            let newSize = increase ? currentFont.pointSize + 2 : max(8, currentFont.pointSize - 2)
            let newFont = NSFontManager.shared.convert(currentFont, toSize: newSize)
            attrs[.font] = newFont
            textView.typingAttributes = attrs
        }
    }

    private func registerUndo(
        for textView: NSTextView, range: NSRange, oldText: NSAttributedString,
        newText: NSAttributedString, actionName: String
    ) {
        textView.undoManager?.registerUndo(withTarget: textView) { [weak self] target in
            target.undoManager?.setActionName(actionName)
            self?.registerUndo(
                for: target, range: range, oldText: newText, newText: oldText,
                actionName: actionName)

            target.textStorage?.beginEditing()
            target.textStorage?.replaceCharacters(in: range, with: oldText)
            target.textStorage?.endEditing()
            target.didChangeText()
        }
    }
}
