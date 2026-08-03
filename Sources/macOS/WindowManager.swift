import Cocoa
import SwiftData
import SwiftUI

extension Notification.Name {
    /// Posted by the title-bar pin toggle and by ⌘P to ask the window manager to flip the
    /// pinned state. Routing it through NotificationCenter keeps ContentView (which is shared
    /// with iOS) and EditorShortcutManager free of any WindowManager reference, and leaves
    /// WindowManager the only writer of the state.
    static let toggleWindowPin = Notification.Name("Heptad.toggleWindowPin")
}

/// Owns the single app window and the two modes it can be in.
///
/// Terminology — the code used to overload the word "pinned", so it is spelled out here:
///
/// - **Panel mode**: the window is the menubar-attached floating `NSPanel`. It is re-anchored
///   under the status item on every show, floats above other apps, and a click anywhere outside
///   it dismisses it. This is what the old `isPinnedToMenubar == true` meant.
/// - **Pinned**: the user-facing state behind the title-bar pin toggle and ⌘P. An ordinary
///   movable window that stays put when the user clicks into another app — what
///   `isPinnedToMenubar == false` used to produce.
///
/// The two are exact opposites (`isPanelMode == !isPinned`). Inside this file "pinned" only
/// ever means the user-facing sense; the ambiguous `isPinnedToMenubar` is gone.
///
/// Pinning does not touch `NSApp.setActivationPolicy`: the app ships with `LSUIElement: true`
/// and stays an accessory app in both modes, so a pinned window has no Dock icon or app menu.
class WindowManager: NSObject, NSWindowDelegate {
    private(set) var window: NSPanel?
    private var hostingView: NSView?

    /// Guard flag to prevent windowDidMove from triggering during initial positioning.
    private var isPositioningPanel = false

    /// The anchor point the drag-away gesture is measured from — where the panel was placed
    /// beneath the status-bar icon, or where it sat when it was unpinned in place.
    private(set) var anchorOrigin: NSPoint = .zero

    /// Distance (in points) the panel must travel from its anchor to become a pinned window.
    private let dragToPinThreshold: CGFloat = AppConstants.Window.dragToPinThreshold

    /// Global event monitor for click-outside-to-dismiss, live only in panel mode.
    private var globalClickMonitor: EventMonitor?

    /// One-shot monitor waiting for mouse-up to complete the drag-away-to-pin transition.
    private var pendingPinMonitor: EventMonitor?

    /// Backing store for the persisted pinned state.
    private let defaults: UserDefaults

    /// Who owns activation, and how Heptad takes and returns it.
    private let activation: ActivationCoordinating

    /// The app that was frontmost when Heptad last took activation, so dismissing the window can
    /// hand focus straight back to it. See `yieldActivation()` for why that is not automatic.
    private var previouslyActiveApp: NSRunningApplication?

    /// Weak reference to the status bar button to prevent dismissal when the user clicks the button itself
    weak var statusBarButton: NSStatusBarButton?

    init(
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        activation: ActivationCoordinating = SystemActivationCoordinator()
    ) {
        self.defaults = defaults
        self.activation = activation
        super.init()

        // No removeObserver needed: selector-based observers auto-unregister on deinit.
        notificationCenter.addObserver(
            self,
            selector: #selector(handleTogglePinRequest),
            name: .toggleWindowPin,
            object: nil
        )

        workspaceNotificationCenter.addObserver(
            self,
            selector: #selector(handleAppActivation),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    // MARK: - API

    func toggleWindow(sender: NSStatusBarButton) {
        self.statusBarButton = sender

        // A pinned window keeps its place, so the menubar icon (and the global hotkey, which
        // lands here too) acts as show/hide for it: bring it forward when another app covers
        // it, hide it only when it is already the window in front.
        if isPinned, let window, window.isVisible {
            if window.isKeyWindow {
                window.performClose(nil)  // delegates to windowShouldClose
            } else {
                window.makeKeyAndOrderFront(nil)
                takeActivation()
            }
            return
        }

        if !(window?.isVisible ?? false) {
            showWindow(sender: sender)
        } else {
            window?.orderOut(nil)
            globalClickMonitor?.stop()
            yieldActivation()
        }
    }

    // MARK: - Activation

    /// Keeps `previouslyActiveApp` current as the user moves between other apps.
    ///
    /// Reading the frontmost app at show time is not reliable on its own: clicking the status
    /// item can make Heptad active before `toggleWindow` runs, at which point the app to hand
    /// focus back to is no longer frontmost. Tracking activations as they happen survives that.
    @objc private func handleAppActivation(_ notification: Notification) {
        guard
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication,
            app != .current
        else { return }
        previouslyActiveApp = app
    }

    /// Activates Heptad, remembering which app it is taking focus from.
    ///
    /// The notification above misses one case — an app that was already frontmost when Heptad
    /// launched never posts an activation — so the frontmost app is also read here as a backstop.
    private func takeActivation() {
        if !activation.isCurrentAppActive, let frontmost = activation.frontmostApplication,
            frontmost != .current {
            previouslyActiveApp = frontmost
        }
        activation.activateCurrentApp()
    }

    /// Hands activation back to whichever app was frontmost before the window was shown.
    ///
    /// Ordering the window out is not enough. Heptad is an accessory app (`LSUIElement`), and
    /// AppKit does not deactivate an app just because its last window went away: Heptad stays the
    /// *active* application with nothing on screen. The app underneath is then drawn frontmost
    /// but never becomes active, so its key window is never told to restore its first responder —
    /// the user sees their editor back with no caret in it until they ⌘-Tab away and return,
    /// which is what forces the real activation.
    private func yieldActivation() {
        // A click outside the panel has already activated whatever was clicked; only step aside
        // when Heptad is still the one holding activation.
        guard activation.isCurrentAppActive else { return }

        if let previous = previouslyActiveApp, previous != .current, !previous.isTerminated {
            activation.activate(previous)
        } else {
            activation.deactivateCurrentApp()
        }
    }

    // MARK: - Pinning

    /// The user-facing pinned state, persisted so it survives closing the window and relaunching.
    var isPinned: Bool { defaults.bool(forKey: AppConstants.windowPinnedKey) }

    /// True while the window behaves as the menubar panel — the inverse of `isPinned`.
    var isPanelMode: Bool { !isPinned }

    /// Persists the pinned state and applies it to the live window, if there is one.
    func setPinned(_ pinned: Bool) {
        defaults.set(pinned, forKey: AppConstants.windowPinnedKey)
        guard let window else { return }
        applyPinnedState(to: window)
    }

    func togglePin() {
        setPinned(!isPinned)
    }

    @objc private func handleTogglePinRequest() {
        togglePin()
    }

    private func applyPinnedState(to window: NSPanel) {
        if isPinned {
            applyPinnedStyling(to: window)
        } else {
            applyPanelStyling(to: window)
        }
    }

    /// Pinned styling: an ordinary movable window that other apps may cover and that never
    /// dismisses itself. `.nonactivatingPanel` deliberately stays in the mask — it only governs
    /// activation on click, and the panel has always kept it in this mode.
    private func applyPinnedStyling(to window: NSPanel) {
        window.styleMask.insert(.miniaturizable)
        window.isFloatingPanel = false
        globalClickMonitor?.stop()
    }

    /// Panel styling: floats above other apps, no miniaturize button, click-outside dismisses.
    private func applyPanelStyling(to window: NSPanel) {
        window.styleMask.insert(.nonactivatingPanel)
        window.styleMask.remove(.miniaturizable)
        window.isFloatingPanel = true

        // Unpinning in place can leave the window far from the status item, so the drag-away
        // gesture is measured from where the window actually is rather than a stale anchor.
        anchorOrigin = window.frame.origin

        if window.isVisible {
            installGlobalClickMonitor()
        } else {
            globalClickMonitor?.stop()
        }
    }

    // MARK: - Window Delegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)

        // The pinned state is deliberately left untouched: it is persisted, and the next show
        // restores it. Only the click monitor has to go — there is nothing left to dismiss.
        globalClickMonitor?.stop()
        yieldActivation()
        return false
    }

    func windowDidMove(_ notification: Notification) {
        guard let movedWindow = notification.object as? NSWindow else { return }

        // Only track moves on the panel (dragging it away is the gesture that pins it)
        guard movedWindow === window, isPanelMode, !isPositioningPanel else { return }

        // When threshold is exceeded, wait for mouse-up before transitioning.
        if panelDragDistance(of: movedWindow) > dragToPinThreshold && pendingPinMonitor == nil {
            pendingPinMonitor = EventMonitor(local: true, mask: .leftMouseUp) { [weak self] event in
                guard let self = self else { return event }
                // Remove the one-shot monitor
                self.pendingPinMonitor?.stop()
                self.pendingPinMonitor = nil

                // Verify we're still in the drag-away state
                if self.isPanelMode, let window = self.window,
                    self.panelDragDistance(of: window) > self.dragToPinThreshold {
                    self.setPinned(true)
                }
                return event
            }
            pendingPinMonitor?.start()
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

    // MARK: - Showing the Window

    private func showWindow(sender: NSStatusBarButton) {
        if window == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 300, height: 400),
                styleMask: [
                    .titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel
                ],
                backing: .buffered, defer: false)

            // AppKit persists and restores the frame; panel mode re-anchors the origin on every show.
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

        // Only the panel is anchored under the status item. A pinned window is restored to
        // wherever the user parked it (AppKit reloads that frame from the autosave), because
        // yanking a deliberately placed window back under the menubar is the opposite of pinning.
        if isPanelMode {
            anchorBelowStatusItem(sender: sender, window: window)
        }

        window.makeKeyAndOrderFront(nil)
        applyPinnedState(to: window)
        takeActivation()
    }

    private func anchorBelowStatusItem(sender: NSStatusBarButton, window: NSPanel) {
        guard sender.window?.screen != nil else { return }

        let buttonRect = sender.window?.convertToScreen(sender.frame) ?? .zero
        let xPos = buttonRect.midX - (window.frame.width / 2)
        let yPos = buttonRect.minY - window.frame.height - 5

        let origin = NSPoint(x: xPos, y: yPos)
        anchorOrigin = origin
        isPositioningPanel = true
        window.setFrameOrigin(origin)
        isPositioningPanel = false
    }

    // MARK: - Global Click Monitor (click-outside to dismiss in panel mode)

    private func installGlobalClickMonitor() {
        globalClickMonitor?.stop()
        globalClickMonitor = EventMonitor(local: false, mask: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self,
                self.isPanelMode,
                let window = self.window,
                window.isVisible
            else { return event }

            // Don't dismiss if the click is on the status bar button
            if let buttonWindow = self.statusBarButton?.window, buttonWindow == event.window {
                return event
            }

            window.orderOut(nil)
            self.globalClickMonitor?.stop()
            self.yieldActivation()
            return event
        }
        globalClickMonitor?.start()
    }
}
