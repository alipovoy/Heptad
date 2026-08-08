import AppKit
import Testing

@testable import Heptad

/// Stands in for `NSApp`/`NSWorkspace` so the activation hand-off can be driven from a test
/// without switching real applications around.
final class SpyActivationCoordinator: ActivationCoordinating {
    var isCurrentAppActive = false
    var frontmostApplication: NSRunningApplication?

    private(set) var activatedApps: [NSRunningApplication] = []
    private(set) var activatedCurrentAppCount = 0
    private(set) var deactivatedCurrentAppCount = 0

    func activateCurrentApp() {
        activatedCurrentAppCount += 1
        isCurrentAppActive = true
    }

    func activate(_ app: NSRunningApplication) {
        activatedApps.append(app)
        isCurrentAppActive = false
    }

    func deactivateCurrentApp() {
        deactivatedCurrentAppCount += 1
        isCurrentAppActive = false
    }
}

/// A real other running app, standing in for "the app the user was in before Heptad".
/// `NSRunningApplication` instances only come from the system, so one is borrowed here.
func anyOtherRunningApplication() -> NSRunningApplication? {
    NSWorkspace.shared.runningApplications.first { $0 != .current && $0.isTerminated == false }
}

extension Trait where Self == ConditionTrait {
    /// Guards the activation hand-off tests, which need a second application to hand focus to.
    ///
    /// Every dev machine and CI runner has one in practice, but it is a fact about the machine
    /// rather than about `WindowManager`, so its absence skips the test instead of failing it.
    static var requiresAnotherRunningApp: Self {
        .enabled(
            if: anyOtherRunningApplication() != nil,
            "No running application other than the test host to hand activation to")
    }
}

/// The AppKit fixture every window-manager suite is built on: a window manager wired to scratch
/// defaults and private notification centres, and a button to anchor its panel under.
///
/// **The button is a stand-in, not a real status item.** `WindowManager` only ever asks its sender
/// for a frame on a screen — see `anchorBelowStatusItem` — so an `NSStatusBarButton` parked in a
/// borderless window at the top of the screen answers every question it asks.
///
/// A real `NSStatusItem` used to be created per test instead, and waited on until the window
/// server granted it a menu-bar slot. That wait was the single flakiest thing in the suite: the
/// slot is granted asynchronously, `deinit` hands it back only when the fixture is actually
/// released, and over a run the items piled up until the menu bar stopped placing them at all.
/// Half the suite failed that way, in the fixture rather than in any assertion, with the failures
/// clustering towards the end of the run. Nothing here touches `NSStatusBar.system` any more, so
/// there is no shared resource left to exhaust and no placement to wait for.
@MainActor
final class WindowManagerFixture {
    let manager: WindowManager
    let notificationCenter: NotificationCenter
    let workspaceNotificationCenter: NotificationCenter
    let activation: SpyActivationCoordinator

    /// The anchor `toggleWindow` is handed, parked far enough from the right-hand edge that a
    /// centred panel fits beside it — so an ordinary show involves no frame correction.
    let statusBarButton: NSStatusBarButton

    private let scratchDefaults: ScratchDefaults

    /// Every window this fixture put on screen, closed together at teardown.
    private var standInWindows: [NSWindow] = []

    init(name: String) throws {
        scratchDefaults = try ScratchDefaults(name: name)
        notificationCenter = NotificationCenter()
        workspaceNotificationCenter = NotificationCenter()
        activation = SpyActivationCoordinator()
        manager = WindowManager(
            defaults: scratchDefaults.defaults,
            notificationCenter: notificationCenter,
            workspaceNotificationCenter: workspaceNotificationCenter,
            activation: activation,
            // Frame autosaving off. AppKit keys it on the name in *standard* defaults, outside
            // the scratch suite above, so the shipping name would have this fixture restoring
            // the installed app's parked frame — and writing its own back over it. That is what
            // made the position assertions pass or fail on what the machine already had.
            frameAutosaveName: "")

        let standIn = try Self.makeStandInStatusBarButton(insetFromRightEdge: 240)
        statusBarButton = standIn.button
        standInWindows = [standIn.host]
    }

    /// `isolated` so the AppKit teardown runs on the main actor wherever the last release lands.
    isolated deinit {
        manager.window?.close()
        standInWindows.forEach { $0.close() }
    }

    // MARK: - Showing the window

    /// Shows the window and returns it, failing the test when either step doesn't work out.
    func showWindow() throws -> NSPanel {
        manager.toggleWindow(sender: statusBarButton)
        return try #require(manager.window, "Window was not created")
    }

    /// Shows the panel well inside the screen with the drag gesture disarmed.
    ///
    /// Parking it away from the edges is what the drag tests need: they move the panel by a few
    /// points and read the distance back, which only holds while AppKit is not constraining the
    /// frame under them. Pinning across the show is how it gets parked — a pinned window is not
    /// re-anchored under the status item — and unpinning in place re-anchors on wherever it now
    /// sits.
    ///
    /// It no longer has to work around the show arming the gesture by itself; `anchorOrigin` is
    /// now read back off the settled frame (#62). The `isAwaitingDragToPinRelease` check below
    /// stays as the assertion that this is still true.
    func showPanelWithACleanAnchor() throws -> NSPanel {
        manager.setPinned(true)
        let window = try showWindow()

        let screen = try #require(window.screen ?? NSScreen.main, "No screen to place the panel on")
        let parked = NSPoint(x: screen.visibleFrame.minX + 200, y: screen.visibleFrame.minY + 200)
        window.setFrameOrigin(parked)
        manager.setPinned(false)

        try #require(window.frame.origin == parked, "AppKit constrained the panel back on screen")
        try #require(manager.anchorOrigin == parked, "Unpinning re-anchors where the panel sits")
        try #require(manager.isAwaitingDragToPinRelease == false, "The gesture starts disarmed")
        return window
    }

    // MARK: - Stand-in windows

    /// A stand-in menubar button parked at the right-hand end of the menu bar, where a centred
    /// panel no longer fits beside it and AppKit has to correct the frame.
    func statusBarButtonAtTheRightScreenEdge() throws -> NSStatusBarButton {
        let standIn = try Self.makeStandInStatusBarButton(insetFromRightEdge: 40)
        standInWindows.append(standIn.host)
        return standIn.button
    }

    /// A stand-in window, for standing in for another app's window or for a window that is not
    /// the panel. Closed with the rest of the fixture.
    func makeStandInWindow() -> NSWindow {
        // `isReleasedWhenClosed` off: AppKit's default of releasing the window on close
        // over-releases it under ARC and takes the test process down with it.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        standInWindows.append(window)
        return window
    }

    /// Builds an `NSStatusBarButton` hosted in a borderless window `inset` points from the
    /// right-hand end of the menu bar — the shape `WindowManager` reads a real status item as.
    private static func makeStandInStatusBarButton(
        insetFromRightEdge inset: CGFloat
    ) throws -> (button: NSStatusBarButton, host: NSWindow) {
        let screen = try #require(NSScreen.main, "No screen to place the stand-in item on")
        let frame = NSRect(
            x: screen.frame.maxX - inset, y: screen.frame.maxY - 24, width: 32, height: 22)

        let host = NSWindow(
            contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false

        let button = NSStatusBarButton(frame: NSRect(origin: .zero, size: frame.size))
        host.contentView?.addSubview(button)
        host.orderFront(nil)

        try #require(host.screen != nil, "`anchorBelowStatusItem` returns early without a screen")
        return (button, host)
    }

    // MARK: - Driving the manager

    /// The move notification AppKit posts for a dragged window, built by hand so the guards in
    /// `windowDidMove` can be driven without a real drag.
    func moveNotification(for window: NSWindow) -> Notification {
        Notification(name: NSWindow.didMoveNotification, object: window)
    }

    /// The other application the `.requiresAnotherRunningApp` trait has already checked for.
    func otherRunningApplication() throws -> NSRunningApplication {
        try #require(
            anyOtherRunningApplication(),
            "Expected at least one other running application to hand activation to")
    }

    func postActivation(of app: NSRunningApplication) {
        workspaceNotificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: NSWorkspace.shared,
            userInfo: [NSWorkspace.applicationUserInfoKey: app])
    }

    // MARK: - Observing notifications

    /// Runs `action` with an observer on `name` and confirms it fired `count` times.
    /// The posts are synchronous, so there is nothing to wait for once `action` returns.
    func expectingNotification(
        _ name: Notification.Name,
        count: Int = 1,
        during action: @MainActor () throws -> Void
    ) async rethrows {
        try await confirmation("\(name.rawValue) is posted", expectedCount: count) { posted in
            let observer = notificationCenter.addObserver(
                forName: name, object: nil, queue: nil
            ) { _ in posted() }
            defer { notificationCenter.removeObserver(observer) }

            try action()
        }
    }

    /// Runs `action` with observers on both `.flushPendingSaves` and `.windowDidHide` and
    /// confirms each fired exactly once.
    func expectingFlushAndHide(during action: @MainActor () throws -> Void) async throws {
        try await confirmation(".flushPendingSaves is posted") { flushed in
            try await confirmation(".windowDidHide is posted") { hidden in
                let flushObserver = notificationCenter.addObserver(
                    forName: .flushPendingSaves, object: nil, queue: nil
                ) { _ in flushed() }
                let hideObserver = notificationCenter.addObserver(
                    forName: .windowDidHide, object: nil, queue: nil
                ) { _ in hidden() }
                defer {
                    notificationCenter.removeObserver(flushObserver)
                    notificationCenter.removeObserver(hideObserver)
                }
                try action()
            }
        }
    }
}
