import Cocoa
import SwiftUI
import SwiftData

class WindowManager: NSObject, NSWindowDelegate {
    private var window: NSPanel?
    private var hostingView: NSView?

    /// The pre-built main menu, only assigned to NSApp.mainMenu in unpinned mode.
    var appMainMenu: NSMenu?

    /// True when using the panel (pinned to menubar). False when using the regular window.
    private var isPinnedToMenubar = true

    /// Guard flag to prevent windowDidMove from triggering during initial positioning.
    private var isPositioningPanel = false

    /// The anchor point where the panel is placed beneath the status-bar icon.
    private var anchorOrigin: NSPoint = .zero

    /// Threshold (in points) for detecting that the user dragged the panel away.
    private let unpinThreshold: CGFloat = AppConstants.Window.unpinThreshold

    /// Global event monitor for click-outside-to-dismiss when pinned.
    private var globalClickMonitor: Any?

    /// One-shot monitor waiting for mouse-up to complete the unpin transition.
    private var pendingUnpinMonitor: Any?

    /// Weak reference to the status bar button to prevent dismissal when the user clicks the button itself
    weak var statusBarButton: NSStatusBarButton?

    // MARK: - API

    func toggleWindow(sender: NSStatusBarButton) {
        self.statusBarButton = sender

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

    // MARK: - Window Delegate

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

    // MARK: - Global Click Monitor (click-outside to dismiss when pinned)

    private func installGlobalClickMonitor() {
        removeGlobalClickMonitor()
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self,
                  self.isPinnedToMenubar,
                  let w = self.window,
                  w.isVisible else { return }

            // Don't dismiss if the click is on the status bar button
            if let buttonWindow = self.statusBarButton?.window,
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
}
