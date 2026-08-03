import XCTest

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

final class WindowManagerTests: XCTestCase {
    var manager: WindowManager!
    var defaults: UserDefaults!
    var suiteName: String!
    var notificationCenter: NotificationCenter!
    var workspaceNotificationCenter: NotificationCenter!
    var activation: SpyActivationCoordinator!
    var mockStatusBarItem: NSStatusItem!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "WindowManagerTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        notificationCenter = NotificationCenter()
        workspaceNotificationCenter = NotificationCenter()
        activation = SpyActivationCoordinator()
        manager = WindowManager(
            defaults: defaults,
            notificationCenter: notificationCenter,
            workspaceNotificationCenter: workspaceNotificationCenter,
            activation: activation)
        mockStatusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    }

    override func tearDownWithError() throws {
        if let window = manager.window {
            window.close()
        }
        manager = nil
        notificationCenter = nil
        workspaceNotificationCenter = nil
        activation = nil
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        NSStatusBar.system.removeStatusItem(mockStatusBarItem)
        mockStatusBarItem = nil
        try super.tearDownWithError()
    }

    /// Shows the window and returns it, failing the test when either step doesn't work out.
    @MainActor
    private func showWindow() throws -> NSPanel {
        let button = try XCTUnwrap(mockStatusBarItem.button, "No status bar button")
        manager.toggleWindow(sender: button)
        return try XCTUnwrap(manager.window, "Window was not created")
    }

    func testInitialState() {
        XCTAssertNil(manager.window, "Window should not exist initially")
        XCTAssertFalse(manager.isPinned, "Expected the window to start unpinned")
        XCTAssertTrue(manager.isPanelMode, "Unpinned means panel mode")
    }

    @MainActor
    func testToggleWindowCreatesPanel() throws {
        let window = try showWindow()

        XCTAssertTrue(window.isVisible, "Window should be visible after toggle")
        XCTAssertTrue(manager.isPanelMode, "Window should still be in panel mode")
        XCTAssertTrue(
            window.styleMask.contains(.nonactivatingPanel), "Should be a non-activating panel")
    }

    @MainActor
    func testPinningTurnsThePanelIntoARegularWindow() throws {
        let window = try showWindow()

        manager.setPinned(true)

        XCTAssertTrue(manager.isPinned, "Should be pinned now")
        XCTAssertFalse(manager.isPanelMode, "Pinned is the opposite of panel mode")
        XCTAssertTrue(
            window.styleMask.contains(.miniaturizable),
            "Pinned window should have miniaturizable mask")
        XCTAssertFalse(window.isFloatingPanel, "Pinned window should not float above all else")
    }

    @MainActor
    func testUnpinningRestoresPanelBehaviourInPlace() throws {
        let window = try showWindow()
        manager.setPinned(true)

        manager.setPinned(false)

        XCTAssertTrue(manager.isPanelMode, "Should be back in panel mode")
        XCTAssertTrue(window.isFloatingPanel, "Panel floats above other apps again")
        XCTAssertFalse(
            window.styleMask.contains(.miniaturizable), "Panel has no miniaturize button")
        XCTAssertTrue(
            window.styleMask.contains(.nonactivatingPanel), "Panel styling is re-applied")
    }

    @MainActor
    func testUnpinningInPlaceReAnchorsTheDragGesture() throws {
        let window = try showWindow()
        manager.setPinned(true)

        // The user parks the pinned window somewhere far from the menubar anchor.
        let parked = NSPoint(x: 400, y: 300)
        window.setFrameOrigin(parked)

        manager.setPinned(false)

        XCTAssertEqual(
            manager.anchorOrigin, window.frame.origin,
            "Drag-away detection must measure from where the window now sits")
    }

    @MainActor
    func testTogglePinFlipsBothWays() throws {
        _ = try showWindow()

        manager.togglePin()
        XCTAssertTrue(manager.isPinned)

        manager.togglePin()
        XCTAssertFalse(manager.isPinned)
    }

    @MainActor
    func testToggleWindowPinNotificationTogglesTheState() throws {
        _ = try showWindow()

        notificationCenter.post(name: .toggleWindowPin, object: nil)
        XCTAssertTrue(manager.isPinned, "The pin button and ⌘P both post this notification")

        notificationCenter.post(name: .toggleWindowPin, object: nil)
        XCTAssertFalse(manager.isPinned)
    }

    @MainActor
    func testPinnedStateIsPersistedAndSurvivesANewManager() throws {
        _ = try showWindow()
        manager.setPinned(true)

        XCTAssertTrue(
            defaults.bool(forKey: AppConstants.windowPinnedKey), "Pinned state must be persisted")

        // Stands in for a relaunch: a fresh manager over the same defaults.
        let relaunched = WindowManager(defaults: defaults)
        XCTAssertTrue(relaunched.isPinned, "Pinned state should survive a relaunch")
    }

    @MainActor
    func testWindowShouldCloseKeepsThePinnedState() throws {
        let window = try showWindow()
        manager.setPinned(true)

        _ = manager.windowShouldClose(window)

        XCTAssertTrue(manager.isPinned, "Closing must not silently unpin the window")
        XCTAssertFalse(window.isVisible, "Window should be closed")
    }

    @MainActor
    func testShowRestoresThePersistedPinnedStateWithoutReAnchoring() throws {
        let window = try showWindow()
        manager.setPinned(true)

        window.setFrameOrigin(NSPoint(x: 420, y: 320))
        let parked = window.frame.origin  // AppKit may constrain the frame to the screen
        _ = manager.windowShouldClose(window)

        let button = try XCTUnwrap(mockStatusBarItem.button, "No status bar button")
        manager.toggleWindow(sender: button)

        XCTAssertTrue(window.isVisible, "Toggling a hidden pinned window shows it again")
        XCTAssertTrue(manager.isPinned, "Pinned state is restored on the next show")
        XCTAssertFalse(window.isFloatingPanel, "Restored as a regular window, not a panel")
        XCTAssertTrue(window.styleMask.contains(.miniaturizable))
        XCTAssertEqual(
            window.frame.origin, parked,
            "A pinned window stays where the user parked it instead of re-anchoring")
    }

    // MARK: - Activation hand-off

    /// A real other running app, standing in for "the app the user was in before Heptad".
    /// `NSRunningApplication` instances only come from the system, so one is borrowed here.
    private func otherRunningApplication() throws -> NSRunningApplication {
        let other = NSWorkspace.shared.runningApplications.first {
            $0 != .current && !$0.isTerminated
        }
        return try XCTUnwrap(other, "Expected at least one other running application")
    }

    private func postActivation(of app: NSRunningApplication) {
        workspaceNotificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: NSWorkspace.shared,
            userInfo: [NSWorkspace.applicationUserInfoKey: app])
    }

    @MainActor
    func testClosingHandsActivationBackToTheAppThatHadIt() throws {
        let previous = try otherRunningApplication()
        postActivation(of: previous)

        let window = try showWindow()
        XCTAssertTrue(activation.isCurrentAppActive, "Showing the window activates Heptad")

        _ = manager.windowShouldClose(window)

        XCTAssertEqual(
            activation.activatedApps.last, previous,
            "Ordering the window out is not enough — the previous app must be reactivated so its "
                + "key window restores first responder")
        XCTAssertEqual(activation.deactivatedCurrentAppCount, 0)
    }

    @MainActor
    func testTogglingTheWindowClosedHandsActivationBack() throws {
        let previous = try otherRunningApplication()
        postActivation(of: previous)
        _ = try showWindow()

        let button = try XCTUnwrap(mockStatusBarItem.button, "No status bar button")
        manager.toggleWindow(sender: button)

        XCTAssertEqual(activation.activatedApps.last, previous)
    }

    @MainActor
    func testShowingFallsBackToTheFrontmostAppWhenNoActivationWasObserved() throws {
        // An app that was already frontmost when Heptad launched never posts an activation.
        let previous = try otherRunningApplication()
        activation.frontmostApplication = previous

        let window = try showWindow()
        _ = manager.windowShouldClose(window)

        XCTAssertEqual(activation.activatedApps.last, previous)
    }

    @MainActor
    func testClosingWithNoKnownPreviousAppJustGivesUpActiveStatus() throws {
        let window = try showWindow()

        _ = manager.windowShouldClose(window)

        XCTAssertTrue(activation.activatedApps.isEmpty, "There is no app to hand activation to")
        XCTAssertEqual(activation.deactivatedCurrentAppCount, 1)
    }

    @MainActor
    func testClosingLeavesActivationAloneWhenAnotherAppAlreadyHasIt() throws {
        postActivation(of: try otherRunningApplication())
        let window = try showWindow()

        // What a click outside the panel looks like: the click already activated the other app.
        activation.isCurrentAppActive = false
        _ = manager.windowShouldClose(window)

        XCTAssertTrue(activation.activatedApps.isEmpty, "Must not steal focus back from the click")
        XCTAssertEqual(activation.deactivatedCurrentAppCount, 0)
    }

    @MainActor
    func testHeptadItselfIsNeverRecordedAsThePreviousApp() throws {
        postActivation(of: .current)
        let window = try showWindow()

        _ = manager.windowShouldClose(window)

        XCTAssertTrue(activation.activatedApps.isEmpty, "Reactivating Heptad would be a no-op loop")
        XCTAssertEqual(activation.deactivatedCurrentAppCount, 1)
    }

    // MARK: - Flushing pending saves
    //
    // The third hide path — the click-outside monitor — is driven by a global NSEvent monitor
    // that only the window server can fire, so it is covered by the same `flushPendingSaves()`
    // call rather than by a test.

    @MainActor
    func testClosingTheWindowFlushesPendingSaves() throws {
        let window = try showWindow()
        let flushed = expectation(
            forNotification: .flushPendingSaves, object: nil,
            notificationCenter: notificationCenter)

        _ = manager.windowShouldClose(window)

        wait(for: [flushed], timeout: 1)
    }

    @MainActor
    func testTogglingTheWindowClosedFlushesPendingSaves() throws {
        _ = try showWindow()
        let flushed = expectation(
            forNotification: .flushPendingSaves, object: nil,
            notificationCenter: notificationCenter)

        let button = try XCTUnwrap(mockStatusBarItem.button, "No status bar button")
        manager.toggleWindow(sender: button)

        wait(for: [flushed], timeout: 1)
    }

    @MainActor
    func testShowingTheWindowDoesNotFlush() throws {
        let flushed = expectation(
            forNotification: .flushPendingSaves, object: nil,
            notificationCenter: notificationCenter)
        flushed.isInverted = true

        _ = try showWindow()

        wait(for: [flushed], timeout: 0.2)
    }

    @MainActor
    func testUnpinnedShowStillAnchorsBelowTheStatusItem() throws {
        let window = try showWindow()
        window.setFrameOrigin(NSPoint(x: 500, y: 500))
        _ = manager.windowShouldClose(window)

        let button = try XCTUnwrap(mockStatusBarItem.button, "No status bar button")
        manager.toggleWindow(sender: button)

        XCTAssertTrue(manager.isPanelMode)
        XCTAssertEqual(
            window.frame.origin, manager.anchorOrigin,
            "The panel is re-anchored under the status item on every show")
    }
}
