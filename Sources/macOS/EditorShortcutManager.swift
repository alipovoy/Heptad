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
}
