import Cocoa

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
        hotKeyManager.register()

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
            let menu = NSMenu()
            menu.addItem(
                NSMenuItem(
                    title: "Quit", action: #selector(NSApplication.terminate(_:)),
                    keyEquivalent: "q"))
            statusBarItem.menu = menu
            statusBarItem.button?.performClick(nil)
            statusBarItem.menu = nil
        } else {
            windowManager.toggleWindow(sender: sender)
        }
    }
}
