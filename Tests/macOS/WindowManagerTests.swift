import AppKit
import Testing

@testable import Heptad

// `WindowManager` owns four separable behaviours — window modes, pinned show/hide, the drag-to-pin
// gesture and the activation hand-off — but one AppKit fixture: a real status item, a real panel
// and a scratch defaults suite, torn down per test. Splitting the file to satisfy the length rules
// would mean either duplicating that fixture per suite or handing it around by reference, for no
// gain in what the tests say.
// swiftlint:disable file_length

/// Stands in for `NSApp`/`NSWorkspace` so the activation hand-off can be driven from a test
/// without switching real applications around.
private final class SpyActivationCoordinator: ActivationCoordinating {
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
private func anyOtherRunningApplication() -> NSRunningApplication? {
    NSWorkspace.shared.runningApplications.first { $0 != .current && $0.isTerminated == false }
}

private extension Trait where Self == ConditionTrait {
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

/// `NSStatusBar.system` and `NSApp` are process-global and every test here drives both, so the
/// suite runs one test at a time on the main actor.
@MainActor
@Suite(.serialized)
// swiftlint:disable:next type_body_length
final class WindowManagerTests {
    private let manager: WindowManager
    private let defaults: UserDefaults
    private let suiteName: String
    private let notificationCenter: NotificationCenter
    private let workspaceNotificationCenter: NotificationCenter
    private let activation: SpyActivationCoordinator
    private let mockStatusBarItem: NSStatusItem

    /// Windows hosting stand-in menubar buttons, closed with the rest of the fixture.
    private var menuBarStandIns: [NSWindow] = []

    init() async throws {
        suiteName = "WindowManagerTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        notificationCenter = NotificationCenter()
        workspaceNotificationCenter = NotificationCenter()
        activation = SpyActivationCoordinator()
        manager = WindowManager(
            defaults: defaults,
            notificationCenter: notificationCenter,
            workspaceNotificationCenter: workspaceNotificationCenter,
            activation: activation)
        mockStatusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // A status item is handed its slot in the menu bar asynchronously. Until that lands its
        // button reports a window parked off screen, `anchorBelowStatusItem` computes a bogus
        // origin from it, and every geometry assertion below measures nothing.
        try await waitUntil("the status item to be placed in the menu bar") {
            guard let statusWindow = mockStatusBarItem.button?.window,
                let screen = statusWindow.screen
            else { return false }
            return statusWindow.frame.maxY >= screen.frame.maxY - 1
        }
    }

    /// `isolated` so the AppKit teardown runs on the main actor wherever the last release lands.
    isolated deinit {
        manager.window?.close()
        menuBarStandIns.forEach { $0.close() }
        defaults.removePersistentDomain(forName: suiteName)
        NSStatusBar.system.removeStatusItem(mockStatusBarItem)
    }

    // MARK: - Fixtures

    /// The status item's button, which `toggleWindow` takes as its anchor.
    private func statusBarButton() throws -> NSStatusBarButton {
        try #require(mockStatusBarItem.button, "No status bar button")
    }

    /// Shows the window and returns it, failing the test when either step doesn't work out.
    private func showWindow() throws -> NSPanel {
        manager.toggleWindow(sender: try statusBarButton())
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
    private func showPanelWithACleanAnchor() throws -> NSPanel {
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

    /// A stand-in window. Created with `isReleasedWhenClosed` off: AppKit's default of releasing
    /// the window on close over-releases it under ARC and takes the test process down with it.
    private func makeStandInWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    /// The move notification AppKit posts for a dragged window, built by hand so the guards in
    /// `windowDidMove` can be driven without a real drag.
    private func moveNotification(for window: NSWindow) -> Notification {
        Notification(name: NSWindow.didMoveNotification, object: window)
    }

    /// Polls until `isSatisfied` holds, or throws once the deadline passes. The window server
    /// grants status-item slots and key-window status on its own schedule, not synchronously
    /// with the call that asks for them.
    private func waitUntil(
        _ condition: String,
        timeout: Duration = .seconds(5),
        isSatisfied: @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while isSatisfied() == false {
            try #require(ContinuousClock.now < deadline, "Timed out waiting for \(condition)")
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: - Modes

    @Test func initialState() {
        #expect(manager.window == nil, "Window should not exist initially")
        #expect(manager.isPinned == false, "Expected the window to start unpinned")
    }

    @Test func toggleWindowCreatesPanel() throws {
        let window = try showWindow()

        #expect(window.isVisible, "Window should be visible after toggle")
        #expect(manager.isPanelMode, "Window should still be in panel mode")
        #expect(window.styleMask.contains(.nonactivatingPanel), "Should be a non-activating panel")
    }

    @Test func pinningTurnsThePanelIntoARegularWindow() throws {
        let window = try showWindow()

        manager.setPinned(true)

        #expect(manager.isPinned, "Should be pinned now")
        #expect(manager.isPanelMode == false, "Pinned is the opposite of panel mode")
        #expect(
            window.styleMask.contains(.miniaturizable),
            "Pinned window should have miniaturizable mask")
        #expect(window.isFloatingPanel == false, "Pinned window should not float above all else")
    }

    @Test func unpinningRestoresPanelBehaviourInPlace() throws {
        let window = try showWindow()
        manager.setPinned(true)

        manager.setPinned(false)

        #expect(manager.isPanelMode, "Should be back in panel mode")
        #expect(window.isFloatingPanel, "Panel floats above other apps again")
        #expect(
            window.styleMask.contains(.miniaturizable) == false,
            "Panel has no miniaturize button")
        #expect(window.styleMask.contains(.nonactivatingPanel), "Panel styling is re-applied")
    }

    @Test func unpinningInPlaceReAnchorsTheDragGesture() throws {
        let window = try showWindow()
        manager.setPinned(true)

        // The user parks the pinned window somewhere far from the menubar anchor.
        let parked = NSPoint(x: 400, y: 300)
        window.setFrameOrigin(parked)

        manager.setPinned(false)

        #expect(
            manager.anchorOrigin == window.frame.origin,
            "Drag-away detection must measure from where the window now sits")
    }

    @Test func togglePinFlipsBothWays() throws {
        _ = try showWindow()

        manager.togglePin()
        #expect(manager.isPinned)

        manager.togglePin()
        #expect(manager.isPinned == false)
    }

    @Test func toggleWindowPinNotificationTogglesTheState() throws {
        _ = try showWindow()

        notificationCenter.post(name: .toggleWindowPin, object: nil)
        #expect(manager.isPinned, "The pin button and ⌘P both post this notification")

        notificationCenter.post(name: .toggleWindowPin, object: nil)
        #expect(manager.isPinned == false)
    }

    @Test func pinnedStateIsPersistedAndSurvivesANewManager() throws {
        _ = try showWindow()
        manager.setPinned(true)

        #expect(
            defaults.bool(forKey: AppConstants.windowPinnedKey), "Pinned state must be persisted")

        // Stands in for a relaunch: a fresh manager over the same defaults.
        let relaunched = WindowManager(defaults: defaults)
        #expect(relaunched.isPinned, "Pinned state should survive a relaunch")
    }

    @Test func windowShouldCloseKeepsThePinnedState() throws {
        let window = try showWindow()
        manager.setPinned(true)

        _ = manager.windowShouldClose(window)

        #expect(manager.isPinned, "Closing must not silently unpin the window")
        #expect(window.isVisible == false, "Window should be closed")
    }

    @Test func showRestoresThePersistedPinnedStateWithoutReAnchoring() throws {
        let window = try showWindow()
        manager.setPinned(true)

        window.setFrameOrigin(NSPoint(x: 420, y: 320))
        let parked = window.frame.origin  // AppKit may constrain the frame to the screen
        _ = manager.windowShouldClose(window)

        manager.toggleWindow(sender: try statusBarButton())

        #expect(window.isVisible, "Toggling a hidden pinned window shows it again")
        #expect(manager.isPinned, "Pinned state is restored on the next show")
        #expect(window.isFloatingPanel == false, "Restored as a regular window, not a panel")
        #expect(window.styleMask.contains(.miniaturizable))
        #expect(
            window.frame.origin == parked,
            "A pinned window stays where the user parked it instead of re-anchoring")
    }

    @Test(.bug(id: 40))
    func unpinnedShowStillAnchorsBelowTheStatusItem() throws {
        let window = try showWindow()
        window.setFrameOrigin(NSPoint(x: 500, y: 500))
        _ = manager.windowShouldClose(window)

        let button = try statusBarButton()
        manager.toggleWindow(sender: button)

        #expect(manager.isPanelMode)

        // Measured against the status button, not against `manager.anchorOrigin`: the latter is
        // re-derived from the window's own frame at the end of every panel show, so comparing the
        // two only ever restates that assignment.
        let buttonRect = try #require(button.window?.convertToScreen(button.frame))
        let screen = try #require(window.screen ?? NSScreen.main, "No screen to anchor against")

        // A status item close to the right-hand edge would put the centred panel partly off
        // screen, and AppKit pulls it back — so the expected x is the ideal one, clamped.
        let idealX = buttonRect.midX - window.frame.width / 2
        let expectedX = min(idealX, screen.visibleFrame.maxX - window.frame.width)
        #expect(abs(window.frame.origin.x - expectedX) <= 1)
        #expect(abs(window.frame.origin.y - (buttonRect.minY - window.frame.height - 5)) <= 1)
    }

    // MARK: - Pinned show/hide
    //
    // A pinned window is neither re-anchored nor dismissed by a click outside, so the menubar
    // icon (and the global hotkey, which lands in the same place) is its show/hide control.

    @Test(.bug(id: 59))
    func togglingAPinnedWindowThatIsNotKeyBringsItForward() throws {
        let window = try showWindow()
        manager.setPinned(true)
        let activationsBefore = activation.activatedCurrentAppCount

        // Stands in for another app's window covering the pinned one: key status sits elsewhere.
        let cover = makeStandInWindow()
        defer { cover.close() }
        cover.makeKeyAndOrderFront(nil)
        try #require(window.isKeyWindow == false, "The pinned window must not be the key window")

        manager.toggleWindow(sender: try statusBarButton())

        #expect(window.isVisible, "A covered pinned window is raised, not hidden")
        #expect(
            activation.activatedCurrentAppCount == activationsBefore + 1,
            "Raising the window is useless without activation — typing would go elsewhere")
    }

    @Test(.bug(id: 59))
    func togglingAPinnedWindowThatIsAlreadyKeyHidesIt() async throws {
        let window = try showWindow()
        manager.setPinned(true)

        // Key status is granted by the window server rather than set, so it is waited for.
        window.makeKeyAndOrderFront(nil)
        try await waitUntil("the pinned window to become key") { window.isKeyWindow }

        manager.toggleWindow(sender: try statusBarButton())

        #expect(window.isVisible == false, "A pinned window already in front hides on toggle")
        #expect(manager.isPinned, "Hiding it must not unpin it")
    }

    // MARK: - Drag to pin

    /// A panel show anchors on where the panel *landed*, so it cannot arm the pin gesture.
    ///
    /// Centred under a status item near the right-hand edge of the screen the panel would hang
    /// off it, and AppKit pulls the frame back — during the ordering, after `anchorBelowStatusItem`
    /// has run. Anchored on the requested origin, that correction measures as a drag of its own
    /// distance, which can be more than the threshold: an ordinary show that involved no drag at
    /// all arms the pin gesture and leaves a mouse-up monitor installed until the next click.
    ///
    /// The edge position is supplied rather than hoped for. The real status item sits wherever
    /// the running Mac's menu bar puts it, and on a layout that leaves the panel fitting there is
    /// no correction to catch — which is exactly why #44 skipped this case.
    @Test(.bug(id: 62))
    func aPanelShowNearAScreenEdgeAnchorsOnWhereThePanelLanded() throws {
        let edgeButton = try statusBarButtonAtTheRightScreenEdge()

        manager.toggleWindow(sender: edgeButton)
        let window = try #require(manager.window, "Window was not created")

        let buttonRect = try #require(edgeButton.window?.convertToScreen(edgeButton.frame))
        try #require(
            abs(window.frame.origin.x - (buttonRect.midX - window.frame.width / 2))
                > AppConstants.Window.dragToPinThreshold,
            "AppKit has to have corrected the frame for this to be testing the correction at all")

        #expect(
            manager.anchorOrigin == window.frame.origin,
            "The anchor must be where the panel actually is, not where it was aimed")
        #expect(manager.panelDragDistance(of: window) == 0, "A show is not a drag")
        #expect(
            manager.isAwaitingDragToPinRelease == false,
            "Showing the panel must not leave a mouse-up monitor armed on an ordinary open")

        // And the correction's own move notification, whenever it is delivered, still measures
        // zero rather than re-arming what the show just declined to arm.
        manager.windowDidMove(moveNotification(for: window))

        #expect(manager.isAwaitingDragToPinRelease == false)
    }

    /// A stand-in menubar button parked at the right-hand end of the menu bar.
    ///
    /// Deliberately not the real status item, and deliberately not a resized panel: the panel
    /// carries `setFrameAutosaveName`, so changing its size writes through to the standard
    /// defaults every other test's panel is restored from — and to the real app's.
    private func statusBarButtonAtTheRightScreenEdge() throws -> NSStatusBarButton {
        let screen = try #require(NSScreen.main, "No screen to place the stand-in item on")
        let frame = NSRect(
            x: screen.frame.maxX - 40, y: screen.frame.maxY - 24, width: 32, height: 22)

        let host = NSWindow(
            contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false
        menuBarStandIns.append(host)

        let button = NSStatusBarButton(frame: NSRect(origin: .zero, size: frame.size))
        host.contentView?.addSubview(button)
        host.orderFront(nil)

        try #require(host.screen != nil, "`anchorBelowStatusItem` returns early without a screen")
        return button
    }

    @Test(.bug(id: 44))
    func dragDistanceIsMeasuredFromTheAnchorNotTheScreenOrigin() throws {
        let window = try showPanelWithACleanAnchor()

        // Sitting on its anchor the panel has travelled nothing, even though it is hundreds of
        // points from the screen origin — far enough to trip the threshold on its own.
        #expect(manager.panelDragDistance(of: window) == 0)
        #expect(
            hypot(window.frame.origin.x, window.frame.origin.y)
                > AppConstants.Window.dragToPinThreshold,
            "Measuring from the screen origin would have armed the gesture already")

        let anchor = manager.anchorOrigin
        window.setFrameOrigin(NSPoint(x: anchor.x, y: anchor.y - 15))

        #expect(abs(manager.panelDragDistance(of: window) - 15) <= 1)
    }

    @Test(
        .bug(id: 44),
        arguments: [
            (AppConstants.Window.dragToPinThreshold - 5, false),
            (AppConstants.Window.dragToPinThreshold + 30, true)
        ])
    func theThresholdDecidesWhetherADragArmsThePinTransition(
        travelled: CGFloat, arms: Bool
    ) throws {
        let window = try showPanelWithACleanAnchor()
        let anchor = manager.anchorOrigin

        window.setFrameOrigin(NSPoint(x: anchor.x, y: anchor.y - travelled))
        manager.windowDidMove(moveNotification(for: window))

        #expect(manager.isAwaitingDragToPinRelease == arms)
        #expect(
            manager.isPinned == false,
            """
            Pinning mid-drag would restyle the window under the user's cursor — the transition \
            waits for mouse-up
            """)
    }

    @Test(.bug(id: 44))
    func movingAPinnedWindowIsNotADragToPinGesture() throws {
        let window = try showPanelWithACleanAnchor()
        manager.setPinned(true)
        let anchor = manager.anchorOrigin

        window.setFrameOrigin(NSPoint(x: anchor.x, y: anchor.y - 100))
        manager.windowDidMove(moveNotification(for: window))

        #expect(
            manager.isAwaitingDragToPinRelease == false,
            "A pinned window is meant to be dragged around; only the panel arms the gesture")
    }

    @Test(.bug(id: 44))
    func aMoveReportedForAnotherWindowIsIgnored() throws {
        _ = try showPanelWithACleanAnchor()

        // Left where it was created, which is far enough from the panel's anchor to arm the
        // gesture if `windowDidMove` did not check which window actually moved.
        let other = makeStandInWindow()
        defer { other.close() }
        try #require(
            manager.panelDragDistance(of: other) > AppConstants.Window.dragToPinThreshold,
            "This window has to be past the threshold for the identity guard to be under test")

        manager.windowDidMove(moveNotification(for: other))

        #expect(manager.isAwaitingDragToPinRelease == false)
    }

    // MARK: - Activation hand-off

    /// The other application the `.requiresAnotherRunningApp` trait has already checked for.
    private func otherRunningApplication() throws -> NSRunningApplication {
        try #require(
            anyOtherRunningApplication(),
            "Expected at least one other running application to hand activation to")
    }

    private func postActivation(of app: NSRunningApplication) {
        workspaceNotificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: NSWorkspace.shared,
            userInfo: [NSWorkspace.applicationUserInfoKey: app])
    }

    @Test(.requiresAnotherRunningApp)
    func closingHandsActivationBackToTheAppThatHadIt() throws {
        let previous = try otherRunningApplication()
        postActivation(of: previous)

        let window = try showWindow()
        #expect(activation.isCurrentAppActive, "Showing the window activates Heptad")

        _ = manager.windowShouldClose(window)

        #expect(
            activation.activatedApps.last == previous,
            """
            Ordering the window out is not enough — the previous app must be reactivated so its \
            key window restores first responder
            """)
        #expect(activation.deactivatedCurrentAppCount == 0)
    }

    @Test(.requiresAnotherRunningApp)
    func togglingTheWindowClosedHandsActivationBack() throws {
        let previous = try otherRunningApplication()
        postActivation(of: previous)
        _ = try showWindow()

        manager.toggleWindow(sender: try statusBarButton())

        #expect(activation.activatedApps.last == previous)
    }

    @Test(.requiresAnotherRunningApp)
    func showingFallsBackToTheFrontmostAppWhenNoActivationWasObserved() throws {
        // An app that was already frontmost when Heptad launched never posts an activation.
        let previous = try otherRunningApplication()
        activation.frontmostApplication = previous

        let window = try showWindow()
        _ = manager.windowShouldClose(window)

        #expect(activation.activatedApps.last == previous)
    }

    @Test func closingWithNoKnownPreviousAppJustGivesUpActiveStatus() throws {
        let window = try showWindow()

        _ = manager.windowShouldClose(window)

        #expect(activation.activatedApps.isEmpty, "There is no app to hand activation to")
        #expect(activation.deactivatedCurrentAppCount == 1)
    }

    @Test(.requiresAnotherRunningApp)
    func closingLeavesActivationAloneWhenAnotherAppAlreadyHasIt() throws {
        postActivation(of: try otherRunningApplication())
        let window = try showWindow()

        // What a click outside the panel looks like: the click already activated the other app.
        activation.isCurrentAppActive = false
        _ = manager.windowShouldClose(window)

        #expect(activation.activatedApps.isEmpty, "Must not steal focus back from the click")
        #expect(activation.deactivatedCurrentAppCount == 0)
    }

    @Test func heptadItselfIsNeverRecordedAsThePreviousApp() throws {
        postActivation(of: .current)
        let window = try showWindow()

        _ = manager.windowShouldClose(window)

        #expect(activation.activatedApps.isEmpty, "Reactivating Heptad would be a no-op loop")
        #expect(activation.deactivatedCurrentAppCount == 1)
    }

    // MARK: - Flushing pending saves
    //
    // The third hide path — the click-outside monitor — is driven by a global NSEvent monitor
    // that only the window server can fire, so it is covered by the same `flushPendingSaves()`
    // call rather than by a test.

    /// Runs `action` with an observer on `.flushPendingSaves` and confirms it fired `count` times.
    /// The post is synchronous, so there is nothing to wait for once `action` returns.
    private func expectingFlush(
        count: Int = 1,
        during action: @MainActor () throws -> Void
    ) async rethrows {
        try await confirmation(".flushPendingSaves is posted", expectedCount: count) { flushed in
            let observer = notificationCenter.addObserver(
                forName: .flushPendingSaves, object: nil, queue: nil
            ) { _ in flushed() }
            defer { notificationCenter.removeObserver(observer) }

            try action()
        }
    }

    @Test func closingTheWindowFlushesPendingSaves() async throws {
        let window = try showWindow()

        await expectingFlush {
            _ = manager.windowShouldClose(window)
        }
    }

    @Test func togglingTheWindowClosedFlushesPendingSaves() async throws {
        _ = try showWindow()

        try await expectingFlush {
            manager.toggleWindow(sender: try statusBarButton())
        }
    }

    @Test func showingTheWindowDoesNotFlush() async throws {
        try await expectingFlush(count: 0) {
            _ = try showWindow()
        }
    }

    // MARK: - Visibility
    //
    // Hiding orders the window out instead of tearing it down, so the hosted ContentView is
    // never unmounted and hears nothing from SwiftUI. These notifications are its only signal,
    // and the relative-time ticker is switched off by them.

    /// Runs `action` with an observer on `name` and confirms it fired `count` times.
    private func expectingNotification(
        _ name: Notification.Name,
        count: Int = 1,
        during action: @MainActor () throws -> Void
    ) async rethrows {
        try await confirmation("\(name.rawValue) is posted", expectedCount: count) { posted in
            let observer = notificationCenter.addObserver(forName: name, object: nil, queue: nil) { _ in
                posted()
            }
            defer { notificationCenter.removeObserver(observer) }

            try action()
        }
    }

    @Test func showingTheWindowAnnouncesItIsVisible() async throws {
        try await expectingNotification(.windowDidBecomeVisible) {
            _ = try showWindow()
        }
    }

    @Test func closingTheWindowAnnouncesTheHide() async throws {
        let window = try showWindow()

        await expectingNotification(.windowDidHide) {
            _ = manager.windowShouldClose(window)
        }
    }

    @Test func togglingTheWindowClosedAnnouncesTheHide() async throws {
        _ = try showWindow()

        try await expectingNotification(.windowDidHide) {
            manager.toggleWindow(sender: try statusBarButton())
        }
    }

    /// Raising a pinned window that another app was covering is not a visibility change — it
    /// was on screen throughout, and announcing a show would restart a ticker already running.
    @Test(.bug(id: 59))
    func raisingAnAlreadyVisiblePinnedWindowAnnouncesNothing() async throws {
        let window = try showWindow()
        manager.setPinned(true)

        let cover = makeStandInWindow()
        defer { cover.close() }
        cover.makeKeyAndOrderFront(nil)
        try #require(window.isKeyWindow == false, "The pinned window must not be the key window")

        try await expectingNotification(.windowDidBecomeVisible, count: 0) {
            manager.toggleWindow(sender: try statusBarButton())
        }
    }
}
