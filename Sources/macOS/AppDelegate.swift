import Cocoa
import OSLog

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarItem: NSStatusItem!
    let windowManager = WindowManager()
    let shortcutManager = EditorShortcutManager()
    let hotKeyManager = GlobalHotKeyManager()

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        self.statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = self.statusBarItem.button {
            button.image = NSImage(resource: .menuBarIcon)
            button.image?.accessibilityDescription = "Heptad"
            button.action = #selector(toggleWindow(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // In pinned mode, NSApp.mainMenu must be nil so that ⌘Z/C/V/X
        // reach NSTextView's keyDown key bindings instead of being
        // intercepted by menu performKeyEquivalent.
        shortcutManager.start()

        // ⌃⌥Space toggles the panel exactly like clicking the status item does — same entry
        // point, so the panel anchors to the icon and click-outside dismissal behaves the same.
        hotKeyManager.onHotKey = { [weak self] in
            guard let self, let button = self.statusBarItem.button else { return }
            self.windowManager.toggleWindow(sender: button)
        }
        // A failure here is not fatal — everything else keeps working, only the hotkey is inert —
        // but the app advertises a summon key and has no settings UI, so a user whose combination
        // is owned by Spotlight or Raycast would otherwise have nothing at all to go on. The
        // right-click menu says so too; see `statusItemMenu`.
        if !hotKeyManager.register() {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "Heptad", category: "hotkey")
                .warning("The global hotkey could not be claimed; another app owns it.")
        }

        // Open the SwiftData store during launch so the first panel open doesn't pay for it.
        _ = HeptadApp.sharedModelContainer
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager.unregister()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // MARK: - Status Bar Toggle

    @objc func toggleWindow(_ sender: NSStatusBarButton) {
        // Accessibility-driven activation (VoiceOver, UI automation) delivers this action
        // with no backing NSEvent; treat that the same as a plain left click.
        if NSApp.currentEvent?.type == .rightMouseUp {
            statusBarItem.menu = statusItemMenu()
            statusBarItem.button?.performClick(nil)
            statusBarItem.menu = nil
        } else {
            windowManager.toggleWindow(sender: sender)
        }
    }

    /// The right-click menu, which carries a disabled line when the summon key could not be
    /// claimed. This menu is the app's only chrome, so it is the only place that can say why the
    /// advertised shortcut does nothing.
    ///
    /// Disabled by having no action rather than by `isEnabled`, which an enclosing menu
    /// recomputes for itself.
    private func statusItemMenu() -> NSMenu {
        let menu = NSMenu()

        if !hotKeyManager.isRegistered {
            menu.addItem(
                NSMenuItem(
                    title: "⌃⌥Space unavailable — another app owns it", action: nil,
                    keyEquivalent: ""))
            menu.addItem(.separator())
        }

        menu.addItem(
            NSMenuItem(
                title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }
}
