import Cocoa
import SwiftUI
import SwiftData

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var statusBarItem: NSStatusItem!

    // MARK: - Single-Window Architecture
    //
    // Pinned mode: NSPanel with .nonactivatingPanel (popover-like)
    // Unpinned mode: Same NSPanel, but styleMask mutated to behave like a regular window.

    private var window: NSPanel?
    private var hostingView: NSView?

    /// The pre-built main menu, only assigned to NSApp.mainMenu in unpinned mode.
    private var appMainMenu: NSMenu?

    /// True when using the panel (pinned to menubar). False when using the regular window.
    private var isPinnedToMenubar = true

    /// Guard flag to prevent windowDidMove from triggering during initial positioning.
    private var isPositioningPanel = false

    /// The anchor point where the panel is placed beneath the status-bar icon.
    private var anchorOrigin: NSPoint = .zero

    /// Threshold (in points) for detecting that the user dragged the panel away.
    private let unpinThreshold: CGFloat = 20

    /// Global event monitor for click-outside-to-dismiss when pinned.
    private var globalClickMonitor: Any?

    /// Local event monitor for ⌘B/⌘I/⌘+/⌘− formatting shortcuts.
    private var localKeyMonitor: Any?

    /// One-shot monitor waiting for mouse-up to complete the unpin transition.
    private var pendingUnpinMonitor: Any?

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
        appMainMenu = buildMainMenu()
        installLocalKeyMonitor()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)

        // Reset to panel mode behind the scenes so the next menubar click is ready
        if !isPinnedToMenubar {
            NSApp.mainMenu = nil
            NSApp.setActivationPolicy(.accessory)

            // Re-apply panel styling
            window?.styleMask.insert(.nonactivatingPanel)
            window?.styleMask.remove(.miniaturizable)
            window?.isFloatingPanel = true

            isPinnedToMenubar = true
        } else {
            removeGlobalClickMonitor()
        }
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
            // If the window is currently unpinned (regular mode), hide it and reset
            if !isPinnedToMenubar, let w = window, w.isVisible {
                w.performClose(nil) // delegates to windowShouldClose
                return
            }

            if window == nil || !window!.isVisible {
                showPanel(sender: sender)
            } else {
                window?.orderOut(nil)
                removeGlobalClickMonitor()
            }
        }
    }

    // MARK: - Hosting View Factory

    private func makeHostingView() -> NSView {
        if let existing = hostingView { return existing }
        let view = ContentView()
            .modelContainer(SevenNotesApp.sharedModelContainer)
        let hv = NSHostingView(rootView: view)
        hostingView = hv
        return hv
    }

    // MARK: - Panel (Pinned Mode)

    private func showPanel(sender: NSStatusBarButton) {
        if window == nil {
            let savedSizeStr = UserDefaults.standard.string(forKey: "LastWindowSize")
            let size = savedSizeStr != nil ? NSSizeFromString(savedSizeStr!) : NSSize(width: 300, height: 400)

            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel, .utilityWindow],
                backing: .buffered, defer: false)

            panel.titlebarAppearsTransparent = false
            panel.titleVisibility = .hidden
            panel.standardWindowButton(.closeButton)?.isHidden = true
            panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
            panel.standardWindowButton(.zoomButton)?.isHidden = true
            panel.isMovableByWindowBackground = true
            panel.isReleasedWhenClosed = false
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = true
            panel.delegate = self
            panel.contentView = makeHostingView()

            self.window = panel
        }

        guard let w = window else { return }

        // Position below the status bar icon.
        if sender.window?.screen != nil {
            let buttonRect = sender.window?.convertToScreen(sender.frame) ?? .zero
            let xPos = buttonRect.midX - (w.frame.width / 2)
            let yPos = buttonRect.minY - w.frame.height - 5

            let origin = NSPoint(x: xPos, y: yPos)
            anchorOrigin = origin
            isPositioningPanel = true
            w.setFrameOrigin(origin)
            isPositioningPanel = false
        }

        isPinnedToMenubar = true
        NSApp.mainMenu = nil  // Ensure menu doesn't steal key equivalents
        installGlobalClickMonitor()

        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Regular Window (Unpinned Mode)

    private func transitionToRegularWindow() {
        guard let w = window else { return }

        // Simply mutate the window styles
        w.styleMask.remove(.nonactivatingPanel)
        w.styleMask.insert(.miniaturizable)
        w.isFloatingPanel = false

        removeGlobalClickMonitor()
        isPinnedToMenubar = false

        // Install menu and activate app — menu bar and Dock icon appear.
        NSApp.mainMenu = appMainMenu
        NSApp.setActivationPolicy(.regular)
        w.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Window Move & Resize Detection

    func windowDidResize(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        UserDefaults.standard.set(NSStringFromSize(w.frame.size), forKey: "LastWindowSize")
    }

    func windowDidMove(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }

        // Only track moves on the panel (for unpinning detection)
        guard w === window, isPinnedToMenubar, !isPositioningPanel else { return }

        let dx = abs(w.frame.origin.x - anchorOrigin.x)
        let dy = abs(w.frame.origin.y - anchorOrigin.y)
        let distance = hypot(dx, dy)

        // When threshold is exceeded, wait for mouse-up before transitioning.
        if distance > unpinThreshold && pendingUnpinMonitor == nil {
            pendingUnpinMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
                guard let self = self else { return event }
                // Remove the one-shot monitor
                if let monitor = self.pendingUnpinMonitor {
                    NSEvent.removeMonitor(monitor)
                    self.pendingUnpinMonitor = nil
                }
                // Verify we're still in the drag-away state
                if self.isPinnedToMenubar, let w = self.window {
                    let dx = abs(w.frame.origin.x - self.anchorOrigin.x)
                    let dy = abs(w.frame.origin.y - self.anchorOrigin.y)
                    if hypot(dx, dy) > self.unpinThreshold {
                        self.transitionToRegularWindow()
                    }
                }
                return event
            }
        }
    }

    // MARK: - Global Click Monitor (click-outside to dismiss when pinned)

    private func installGlobalClickMonitor() {
        removeGlobalClickMonitor()
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self,
                  self.isPinnedToMenubar,
                  let w = self.window,
                  w.isVisible else { return }

            // Don't dismiss if the click is on the status bar button
            if let buttonWindow = self.statusBarItem.button?.window,
               buttonWindow == event.window {
                return
            }

            w.orderOut(nil)
            self.removeGlobalClickMonitor()
        }
    }

    private func removeGlobalClickMonitor() {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
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
            let currentFont = attrs[.font] as? NSFont ?? NSFont.systemFont(ofSize: 16)
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
            let currentFont = attrs[.font] as? NSFont ?? NSFont.systemFont(ofSize: 16)
            let newSize = increase ? currentFont.pointSize + 2 : max(8, currentFont.pointSize - 2)
            let newFont = NSFontManager.shared.convert(currentFont, toSize: newSize)
            attrs[.font] = newFont
            textView.typingAttributes = attrs
        }
    }

    // MARK: - Main Menu (built once, assigned only in unpinned mode)

    private func buildMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About 7Notes", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit 7Notes", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Edit menu
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // Format menu
        let formatMenuItem = NSMenuItem()
        let formatMenu = NSMenu(title: "Format")

        let fontMenuItem = NSMenuItem()
        let fontMenu = NSMenu(title: "Font")

        let boldItem = fontMenu.addItem(withTitle: "Bold", action: #selector(NSFontManager.addFontTrait(_:)), keyEquivalent: "b")
        boldItem.tag = Int(NSFontTraitMask.boldFontMask.rawValue)

        let italicItem = fontMenu.addItem(withTitle: "Italic", action: #selector(NSFontManager.addFontTrait(_:)), keyEquivalent: "i")
        italicItem.tag = Int(NSFontTraitMask.italicFontMask.rawValue)

        fontMenu.addItem(.separator())

        let biggerItem = fontMenu.addItem(withTitle: "Bigger", action: #selector(NSFontManager.modifyFont(_:)), keyEquivalent: "+")
        biggerItem.tag = 3 // NSSizeUpFontAction

        let smallerItem = fontMenu.addItem(withTitle: "Smaller", action: #selector(NSFontManager.modifyFont(_:)), keyEquivalent: "-")
        smallerItem.tag = 4 // NSSizeDownFontAction

        fontMenuItem.submenu = fontMenu
        formatMenu.addItem(fontMenuItem)

        formatMenuItem.submenu = formatMenu
        mainMenu.addItem(formatMenuItem)

        return mainMenu
    }
}
