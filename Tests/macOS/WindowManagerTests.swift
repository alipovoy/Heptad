import XCTest

@testable import Heptad

final class WindowManagerTests: XCTestCase {
    var manager: WindowManager!
    var defaults: UserDefaults!
    var suiteName: String!
    var notificationCenter: NotificationCenter!
    var mockStatusBarItem: NSStatusItem!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "WindowManagerTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        notificationCenter = NotificationCenter()
        manager = WindowManager(defaults: defaults, notificationCenter: notificationCenter)
        mockStatusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    }

    override func tearDownWithError() throws {
        if let window = manager.window {
            window.close()
        }
        manager = nil
        notificationCenter = nil
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
