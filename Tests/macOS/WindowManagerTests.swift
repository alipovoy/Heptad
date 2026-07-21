import XCTest

@testable import Heptad

final class WindowManagerTests: XCTestCase {
    var manager: WindowManager!
    var mockStatusBarItem: NSStatusItem!

    override func setUp() {
        super.setUp()
        manager = WindowManager()
        mockStatusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    }

    override func tearDown() {
        if let window = manager.window {
            window.close()
        }
        manager = nil
        NSStatusBar.system.removeStatusItem(mockStatusBarItem)
        mockStatusBarItem = nil
        super.tearDown()
    }

    func testInitialState() {
        XCTAssertNil(manager.window, "Window should not exist initially")
        XCTAssertTrue(manager.isPinnedToMenubar, "Expected panel to be pinned initially")
    }

    @MainActor
    func testToggleWindowCreatesPanel() {
        guard let button = mockStatusBarItem.button else {
            XCTFail("No button")
            return
        }

        manager.toggleWindow(sender: button)

        guard let window = manager.window else {
            XCTFail("Window was not created")
            return
        }

        XCTAssertTrue(window.isVisible, "Window should be visible after toggle")
        XCTAssertTrue(manager.isPinnedToMenubar, "Window should still be pinned")
        XCTAssertTrue(
            window.styleMask.contains(.nonactivatingPanel), "Should be a non-activating panel")
    }

    @MainActor
    func testTransitionToRegularWindow() {
        guard let button = mockStatusBarItem.button else {
            XCTFail("No button")
            return
        }

        // 1. Create panel
        manager.toggleWindow(sender: button)
        guard let window = manager.window else {
            XCTFail("Window was not created")
            return
        }

        // 2. Trigger transition
        manager.transitionToRegularWindow()

        // 3. Verify state changes
        XCTAssertFalse(manager.isPinnedToMenubar, "Should be unpinned now")
        XCTAssertTrue(
            window.styleMask.contains(.miniaturizable),
            "Regular window should have miniaturizable mask")
        XCTAssertFalse(window.isFloatingPanel, "Regular window should not float above all else")
    }

    @MainActor
    func testWindowShouldCloseResetsToPinnedState() {
        guard let button = mockStatusBarItem.button else { return }
        manager.toggleWindow(sender: button)
        manager.transitionToRegularWindow()

        XCTAssertFalse(manager.isPinnedToMenubar)

        guard let window = manager.window else { return }
        _ = manager.windowShouldClose(window)

        XCTAssertTrue(manager.isPinnedToMenubar, "State should be reset to pinned")
        XCTAssertFalse(window.isVisible, "Window should be closed")
        XCTAssertTrue(window.styleMask.contains(.nonactivatingPanel), "Resets style mask")
    }
}
