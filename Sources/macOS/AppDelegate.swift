import Cocoa
import SwiftUI
import SwiftData

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarItem: NSStatusItem!
    let windowManager = WindowManager()

    /// Local event monitor for ⌘B/⌘I/⌘+/⌘− formatting shortcuts.
    private var localKeyMonitor: Any?

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        self.statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = self.statusBarItem.button {
            button.image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "7Notes")
            button.action = #selector(toggleWindow(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Build menu once, but DON'T assign to NSApp.mainMenu yet.
        // In pinned mode, NSApp.mainMenu must be nil so that ⌘Z/C/V/X
        // reach NSTextView's keyDown key bindings instead of being
        // intercepted by menu performKeyEquivalent.
        windowManager.appMainMenu = AppMenuBuilder.build()
        installLocalKeyMonitor()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // MARK: - Status Bar Toggle

    @objc func toggleWindow(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent!

        if event.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
            statusBarItem.menu = menu
            statusBarItem.button?.performClick(nil)
            statusBarItem.menu = nil
        } else {
            windowManager.toggleWindow(sender: sender)
        }
    }



    // MARK: - Local Key Monitor (⌘B/⌘I/⌘+/⌘− formatting)
    //
    // Intercepts key-down events within the app and applies formatting
    // to the first responder NSTextView. Does NOT override performKeyEquivalent,
    // so NSTextView's native ⌘C/⌘V/⌘X/⌘Z handling via keyDown key bindings
    // is completely untouched.

    private func installLocalKeyMonitor() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }

            // Only handle ⌘ without option/control
            guard event.modifierFlags.contains(.command),
                  !event.modifierFlags.contains(.option),
                  !event.modifierFlags.contains(.control) else {
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
                return nil // consumed
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
            default:
                return event // pass through
            }
        }
    }

    // MARK: - Font Formatting Helpers

    private func toggleFontTrait(_ trait: NSFontTraitMask, on textView: NSTextView) {
        let fm = NSFontManager.shared
        let range = textView.selectedRange()

        if range.length > 0 {
            guard let textStorage = textView.textStorage else { return }
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
        } else {
            var attrs = textView.typingAttributes
            let currentFont = attrs[.font] as? NSFont ?? NSFont.systemFont(ofSize: AppConstants.UI.defaultFontSize)
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

    private func changeFontSize(increase: Bool, on textView: NSTextView) {
        let range = textView.selectedRange()

        if range.length > 0 {
            guard let textStorage = textView.textStorage else { return }
            textStorage.beginEditing()
            textStorage.enumerateAttribute(.font, in: range, options: []) { value, attrRange, _ in
                guard let oldFont = value as? NSFont else { return }
                let newSize = increase ? oldFont.pointSize + 2 : max(8, oldFont.pointSize - 2)
                let newFont = NSFontManager.shared.convert(oldFont, toSize: newSize)
                textStorage.addAttribute(.font, value: newFont, range: attrRange)
            }
            textStorage.endEditing()
            textView.didChangeText()
        } else {
            var attrs = textView.typingAttributes
            let currentFont = attrs[.font] as? NSFont ?? NSFont.systemFont(ofSize: AppConstants.UI.defaultFontSize)
            let newSize = increase ? currentFont.pointSize + 2 : max(8, currentFont.pointSize - 2)
            let newFont = NSFontManager.shared.convert(currentFont, toSize: newSize)
            attrs[.font] = newFont
            textView.typingAttributes = attrs
        }
    }

}
