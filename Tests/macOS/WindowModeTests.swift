import AppKit
import Testing

@testable import Heptad

/// The two modes `WindowManager` owns — the menubar-attached panel and the pinned window — and
/// the transitions between them.
///
/// Serialized with every other window-server suite by its parent, because each test puts a real
/// window on screen and the AppKit state behind that is process-wide; the fixture is per-test.
extension WindowServerTests {
    /// Nested for the window server — see `WindowServerTests`.
    @MainActor
    @Suite struct WindowModeTests {
        private let fixture: WindowManagerFixture
        private var manager: WindowManager { fixture.manager }

        init() throws {
            fixture = try WindowManagerFixture()
        }

        /// Where the panel's bottom edge belongs when it is hanging under the status item — read from
        /// the same constant the manager positions with, rather than restating its arithmetic.
        private func anchoredY(of window: NSWindow, under button: CGRect) -> CGFloat {
            button.minY - window.frame.height - AppConstants.Window.statusItemGap
        }

        @Test func toggleWindowCreatesPanel() throws {
            let window = try fixture.showWindow()

            #expect(window.isVisible, "Window should be visible after toggle")
            #expect(manager.isPanelMode, "Window should still be in panel mode")
        }

        @Test func pinningDetachesTheWindowFromTheStatusItem() throws {
            let window = try fixture.showWindow()

            manager.setPinned(true)

            #expect(manager.isPinned, "Should be pinned now")
            #expect(manager.isPanelMode == false, "Pinned is the opposite of panel mode")
            #expect(window.isFloatingPanel, "A detached window stays above other apps")
        }

        /// P1-8: minimising was the one way off the screen that did not go through `hide(_:)`, so a
        /// minimised window came back still detached, with no flush and no `.windowDidHide` behind it.
        /// The mask is fixed at creation now, so there is no branch that can put the button back.
        @Test func theWindowIsNeverMiniaturizableInEitherMode() throws {
            let window = try fixture.showWindow()

            #expect(window.styleMask.contains(.miniaturizable) == false, "as the panel")

            manager.setPinned(true)
            #expect(window.styleMask.contains(.miniaturizable) == false, "and once detached")

            manager.setPinned(false)
            #expect(window.styleMask.contains(.miniaturizable) == false, "and reattaching leaves it off")
        }

        /// Both modes float; the level is set once, at creation. Detaching only changes the anchor
        /// and click-outside dismissal.
        @Test func bothModesFloatAboveOtherApps() throws {
            let window = try fixture.showWindow()

            #expect(window.isFloatingPanel, "as the panel")

            manager.setPinned(true)
            #expect(window.isFloatingPanel, "and once detached")

            _ = manager.windowShouldClose(window)
            #expect(window.isFloatingPanel, "and after the close that reattaches it")
        }

        /// #127: `.nonactivatingPanel` takes key focus without making Heptad active, so a detached
        /// window could be clicked, or picked in Mission Control, and the app stayed in the background
        /// with only the status item to get it back.
        ///
        /// Asserted in both modes and across a transition, because the first attempt at this fix
        /// toggled the mask per mode and that is exactly what does not work: the flag is read when the
        /// window is created. It has to be absent from construction and stay absent.
        @Test(.bug(id: 127))
        func theWindowNeverCarriesTheNonActivatingMask() throws {
            let window = try fixture.showWindow()

            #expect(window.styleMask.contains(.nonactivatingPanel) == false, "as the panel")
            #expect(
                window.becomesKeyOnlyIfNeeded == false,
                "and a click anywhere in it makes it key")

            manager.setPinned(true)
            #expect(window.styleMask.contains(.nonactivatingPanel) == false, "and once detached")

            manager.setPinned(false)
            #expect(
                window.styleMask.contains(.nonactivatingPanel) == false,
                "and reattaching does not put it back")
        }

        /// Unpinning leaves the window where it is — it is not yanked back under the status item until
        /// the next show. So the drag-away gesture has to be re-armed from where the window actually
        /// is, or the distance from a stale anchor immediately reads as a drag.
        @Test func unpinningRestoresPanelBehaviourInPlace() throws {
            let window = try fixture.showWindow()
            manager.setPinned(true)
            window.setFrameOrigin(NSPoint(x: 420, y: 320))

            manager.setPinned(false)

            #expect(manager.isPanelMode, "Should be back in panel mode")
            #expect(window.frame.origin == manager.anchorOrigin, "measured from where it was parked")
            #expect(
                manager.panelDragDistance(of: window) <= WindowManager.dragToPinThreshold,
                "so unpinning in place does not read as a drag away")
        }

        @Test func toggleWindowPinNotificationTogglesTheState() throws {
            _ = try fixture.showWindow()

            fixture.notificationCenter.post(name: .toggleWindowPin, object: nil)
            #expect(manager.isPinned, "The pin button and ⌘P both post this notification")

            fixture.notificationCenter.post(name: .toggleWindowPin, object: nil)
            #expect(manager.isPinned == false)
        }

        /// #123: pinning is state, not a preference. It lasts as long as the window is on screen,
        /// and closing puts the panel back — otherwise one drag past the threshold left the app
        /// detached forever, with no click-outside dismissal and no way back most users would find.
        @Test(.bug(id: 123))
        func hidingAPinnedWindowReattachesIt() throws {
            let window = try fixture.showWindow()
            manager.setPinned(true)

            _ = manager.windowShouldClose(window)

            #expect(window.isVisible == false, "Window should be closed")
            #expect(manager.isPanelMode, "Hiding reattaches the window")
            #expect(fixture.state.isPinned == false, "The pin toggle sees the same state")
        }

        @Test(.bug(id: 123))
        func theNextShowIsAPanelAnchoredUnderTheStatusItemAgain() throws {
            let window = try fixture.showWindow()
            manager.setPinned(true)
            window.setFrameOrigin(NSPoint(x: 420, y: 320))
            _ = manager.windowShouldClose(window)

            let button = fixture.statusBarButton
            manager.toggleWindow(sender: button)

            #expect(window.isVisible, "Toggling a hidden window shows it again")
            #expect(manager.isPanelMode, "as the panel, whatever it was when it went away")

            let buttonRect = try #require(button.window?.convertToScreen(button.frame))
            #expect(
                abs(window.frame.origin.y - anchoredY(of: window, under: buttonRect)) <= 1,
                "A reattached window is anchored under the status item, not left where it was parked")
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
            #expect(abs(window.frame.origin.y - anchoredY(of: window, under: buttonRect)) <= 1)
        }
    }
}
