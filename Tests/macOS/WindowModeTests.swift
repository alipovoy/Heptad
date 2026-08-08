import AppKit
import Testing

@testable import Heptad

/// The two modes `WindowManager` owns — the menubar-attached panel and the pinned window — and
/// the transitions between them.
///
/// `.serialized` because each test puts a real window on screen and the AppKit state behind that
/// is process-wide; the fixture itself is per-test.
@MainActor
@Suite(.serialized, .tags(.windowServer))
struct WindowModeTests {
    private let fixture: WindowManagerFixture
    private var manager: WindowManager { fixture.manager }

    init() throws {
        fixture = try WindowManagerFixture(name: "WindowModeTests")
    }

    @Test func toggleWindowCreatesPanel() throws {
        let window = try fixture.showWindow()

        #expect(window.isVisible, "Window should be visible after toggle")
        #expect(manager.isPanelMode, "Window should still be in panel mode")
        #expect(window.styleMask.contains(.nonactivatingPanel), "Should be a non-activating panel")
    }

    @Test func pinningTurnsThePanelIntoARegularWindow() throws {
        let window = try fixture.showWindow()

        manager.setPinned(true)

        #expect(manager.isPinned, "Should be pinned now")
        #expect(manager.isPanelMode == false, "Pinned is the opposite of panel mode")
        #expect(
            window.styleMask.contains(.miniaturizable),
            "Pinned window should have miniaturizable mask")
        #expect(window.isFloatingPanel == false, "Pinned window should not float above all else")
    }

    @Test func unpinningRestoresPanelBehaviourInPlace() throws {
        let window = try fixture.showWindow()
        manager.setPinned(true)

        manager.setPinned(false)

        #expect(manager.isPanelMode, "Should be back in panel mode")
        #expect(window.isFloatingPanel, "Panel floats above other apps again")
        #expect(
            window.styleMask.contains(.miniaturizable) == false,
            "Panel has no miniaturize button")
        #expect(window.styleMask.contains(.nonactivatingPanel), "Panel styling is re-applied")
    }

    @Test func toggleWindowPinNotificationTogglesTheState() throws {
        _ = try fixture.showWindow()

        fixture.notificationCenter.post(name: .toggleWindowPin, object: nil)
        #expect(manager.isPinned, "The pin button and ⌘P both post this notification")

        fixture.notificationCenter.post(name: .toggleWindowPin, object: nil)
        #expect(manager.isPinned == false)
    }

    @Test func windowShouldCloseKeepsThePinnedState() throws {
        let window = try fixture.showWindow()
        manager.setPinned(true)

        _ = manager.windowShouldClose(window)

        #expect(manager.isPinned, "Closing must not silently unpin the window")
        #expect(window.isVisible == false, "Window should be closed")
    }

    @Test func showRestoresThePersistedPinnedStateWithoutReAnchoring() throws {
        let window = try fixture.showWindow()
        manager.setPinned(true)

        window.setFrameOrigin(NSPoint(x: 420, y: 320))
        let parked = window.frame.origin  // AppKit may constrain the frame to the screen
        _ = manager.windowShouldClose(window)

        manager.toggleWindow(sender: fixture.statusBarButton)

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
        let window = try fixture.showWindow()
        window.setFrameOrigin(NSPoint(x: 500, y: 500))
        _ = manager.windowShouldClose(window)

        let button = fixture.statusBarButton
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
}
