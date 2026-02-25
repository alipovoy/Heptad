import Cocoa
import SwiftData
import SwiftUI

class WindowManager: NSObject, NSWindowDelegate {
    private(set) var window: NSPanel?
    private var hostingView: NSView?

    /// True when using the panel (pinned to menubar). False when using the regular window.
    private(set) var isPinnedToMenubar = true

    /// Guard flag to prevent windowDidMove from triggering during initial positioning.
    private var isPositioningPanel = false

    /// The anchor point where the panel is placed beneath the status-bar icon.
    private(set) var anchorOrigin: NSPoint = .zero

    /// Threshold (in points) for detecting that the user dragged the panel away.
    private let unpinThreshold: CGFloat = AppConstants.Window.unpinThreshold

    /// Global event monitor for click-outside-to-dismiss when pinned.
    private var globalClickMonitor: EventMonitor?

    /// One-shot monitor waiting for mouse-up to complete the unpin transition.
    private var pendingUnpinMonitor: EventMonitor?

    /// Weak reference to the status bar button to prevent dismissal when the user clicks the button itself
    weak var statusBarButton: NSStatusBarButton?

    // MARK: - API

    func toggleWindow(sender: NSStatusBarButton) {
        self.statusBarButton = sender

        // If the window is currently unpinned (regular mode), hide it and reset
        if !isPinnedToMenubar, let w = window, w.isVisible {
            w.performClose(nil)  // delegates to windowShouldClose
            return
        }

        if window == nil || !window!.isVisible {
            showPanel(sender: sender)
        } else {
            window?.orderOut(nil)
            globalClickMonitor?.stop()
        }
    }

    // MARK: - Window Delegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)

        // Reset to panel mode behind the scenes so the next menubar click is ready
        if !isPinnedToMenubar {

            // Re-apply panel styling
            window?.styleMask.insert(.nonactivatingPanel)
            window?.styleMask.remove(.miniaturizable)
            window?.isFloatingPanel = true

            isPinnedToMenubar = true
        } else {
            globalClickMonitor?.stop()
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
            pendingUnpinMonitor = EventMonitor(local: true, mask: .leftMouseUp) {
                [weak self] event in
                guard let self = self else { return event }
                // Remove the one-shot monitor
                self.pendingUnpinMonitor?.stop()
                self.pendingUnpinMonitor = nil

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
            pendingUnpinMonitor?.start()
        }
    }

    // MARK: - Hosting View

    private lazy var mainHostingView: NSView = {
        let view = ContentView()
            .modelContainer(SevenNotesApp.sharedModelContainer)
        return NSHostingView(rootView: view)
    }()

    // MARK: - Panel (Pinned Mode)

    private func showPanel(sender: NSStatusBarButton) {
        if window == nil {
            let savedSizeStr = UserDefaults.standard.string(forKey: "LastWindowSize")
            let size =
                savedSizeStr != nil
                ? NSSizeFromString(savedSizeStr!) : NSSize(width: 300, height: 400)

            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
                styleMask: [
                    .titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel,
                ],
                backing: .buffered, defer: false)

            panel.titlebarAppearsTransparent = true
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
            panel.contentView = mainHostingView

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
        installGlobalClickMonitor()

        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Regular Window (Unpinned Mode)

    func transitionToRegularWindow() {
        guard let w = window else { return }

        // Simply mutate the window styles
        w.styleMask.insert(.miniaturizable)
        w.isFloatingPanel = false

        globalClickMonitor?.stop()
        isPinnedToMenubar = false
    }

    // MARK: - Global Click Monitor (click-outside to dismiss when pinned)

    private func installGlobalClickMonitor() {
        globalClickMonitor?.stop()
        globalClickMonitor = EventMonitor(local: false, mask: [.leftMouseDown, .rightMouseDown]) {
            [weak self] event in
            guard let self = self,
                self.isPinnedToMenubar,
                let w = self.window,
                w.isVisible
            else { return event }

            // Don't dismiss if the click is on the status bar button
            if let buttonWindow = self.statusBarButton?.window,
                buttonWindow == event.window
            {
                return event
            }

            w.orderOut(nil)
            self.globalClickMonitor?.stop()
            return event
        }
        globalClickMonitor?.start()
    }
}
