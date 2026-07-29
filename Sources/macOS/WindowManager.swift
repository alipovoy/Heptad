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
        if !isPinnedToMenubar, let window, window.isVisible {
            window.performClose(nil)  // delegates to windowShouldClose
            return
        }

        if !(window?.isVisible ?? false) {
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

    func windowDidMove(_ notification: Notification) {
        guard let movedWindow = notification.object as? NSWindow else { return }

        // Only track moves on the panel (for unpinning detection)
        guard movedWindow === window, isPinnedToMenubar, !isPositioningPanel else { return }

        // When threshold is exceeded, wait for mouse-up before transitioning.
        if panelDragDistance(of: movedWindow) > unpinThreshold && pendingUnpinMonitor == nil {
            pendingUnpinMonitor = EventMonitor(local: true, mask: .leftMouseUp) { [weak self] event in
                guard let self = self else { return event }
                // Remove the one-shot monitor
                self.pendingUnpinMonitor?.stop()
                self.pendingUnpinMonitor = nil

                // Verify we're still in the drag-away state
                if self.isPinnedToMenubar, let window = self.window,
                    self.panelDragDistance(of: window) > self.unpinThreshold {
                    self.transitionToRegularWindow()
                }
                return event
            }
            pendingUnpinMonitor?.start()
        }
    }

    private func panelDragDistance(of window: NSWindow) -> CGFloat {
        hypot(window.frame.origin.x - anchorOrigin.x, window.frame.origin.y - anchorOrigin.y)
    }

    // MARK: - Hosting View

    private lazy var mainHostingView: NSView = {
        let view = ContentView()
            .modelContainer(HeptadApp.sharedModelContainer)
        return NSHostingView(rootView: view)
    }()

    // MARK: - Panel (Pinned Mode)

    private func showPanel(sender: NSStatusBarButton) {
        if window == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 300, height: 400),
                styleMask: [
                    .titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel
                ],
                backing: .buffered, defer: false)

            // AppKit persists and restores the frame; pinned mode re-anchors the origin on every show.
            panel.setFrameAutosaveName("HeptadPanel")

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

        guard let window else { return }

        // Position below the status bar icon.
        if sender.window?.screen != nil {
            let buttonRect = sender.window?.convertToScreen(sender.frame) ?? .zero
            let xPos = buttonRect.midX - (window.frame.width / 2)
            let yPos = buttonRect.minY - window.frame.height - 5

            let origin = NSPoint(x: xPos, y: yPos)
            anchorOrigin = origin
            isPositioningPanel = true
            window.setFrameOrigin(origin)
            isPositioningPanel = false
        }

        isPinnedToMenubar = true
        installGlobalClickMonitor()

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Regular Window (Unpinned Mode)

    func transitionToRegularWindow() {
        guard let window else { return }

        // Simply mutate the window styles
        window.styleMask.insert(.miniaturizable)
        window.isFloatingPanel = false

        globalClickMonitor?.stop()
        isPinnedToMenubar = false
    }

    // MARK: - Global Click Monitor (click-outside to dismiss when pinned)

    private func installGlobalClickMonitor() {
        globalClickMonitor?.stop()
        globalClickMonitor = EventMonitor(local: false, mask: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self,
                self.isPinnedToMenubar,
                let window = self.window,
                window.isVisible
            else { return event }

            // Don't dismiss if the click is on the status bar button
            if let buttonWindow = self.statusBarButton?.window, buttonWindow == event.window {
                return event
            }

            window.orderOut(nil)
            self.globalClickMonitor?.stop()
            return event
        }
        globalClickMonitor?.start()
    }
}
