import AppKit
import Testing

@testable import Heptad

/// Dragging the panel away from its anchor is what pins it. Everything here is about *when* that
/// gesture arms: the distance it is measured over, the threshold, and the three states that must
/// not arm it at all.
@MainActor
@Suite(.serialized, .tags(.windowServer))
struct WindowDragToPinTests {
    private let fixture: WindowManagerFixture
    private var manager: WindowManager { fixture.manager }

    init() throws {
        fixture = try WindowManagerFixture(name: "WindowDragToPinTests")
    }

    /// A panel show anchors on where the panel *landed*, so it cannot arm the pin gesture.
    ///
    /// Centred under a status item near the right-hand edge of the screen the panel would hang
    /// off it, and AppKit pulls the frame back — during the ordering, after `anchorBelowStatusItem`
    /// has run. Anchored on the requested origin, that correction measures as a drag of its own
    /// distance, which can be more than the threshold: an ordinary show that involved no drag at
    /// all arms the pin gesture and leaves a mouse-up monitor installed until the next click.
    ///
    /// The edge position is supplied rather than hoped for. A status item sits wherever the
    /// running Mac's menu bar puts it, and on a layout that leaves the panel fitting there is no
    /// correction to catch — which is exactly why #44 skipped this case.
    @Test(.bug(id: 62))
    func aPanelShowNearAScreenEdgeAnchorsOnWhereThePanelLanded() throws {
        let edgeButton = try fixture.statusBarButtonAtTheRightScreenEdge()

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
        manager.windowDidMove(fixture.moveNotification(for: window))

        #expect(manager.isAwaitingDragToPinRelease == false)
    }

    @Test(.bug(id: 44))
    func dragDistanceIsMeasuredFromTheAnchorNotTheScreenOrigin() throws {
        let window = try fixture.showPanelWithACleanAnchor()

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
        let window = try fixture.showPanelWithACleanAnchor()
        let anchor = manager.anchorOrigin

        window.setFrameOrigin(NSPoint(x: anchor.x, y: anchor.y - travelled))
        manager.windowDidMove(fixture.moveNotification(for: window))

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
        let window = try fixture.showPanelWithACleanAnchor()
        manager.setPinned(true)
        let anchor = manager.anchorOrigin

        window.setFrameOrigin(NSPoint(x: anchor.x, y: anchor.y - 100))
        manager.windowDidMove(fixture.moveNotification(for: window))

        #expect(
            manager.isAwaitingDragToPinRelease == false,
            "A pinned window is meant to be dragged around; only the panel arms the gesture")
    }

    @Test(.bug(id: 44))
    func aMoveReportedForAnotherWindowIsIgnored() throws {
        _ = try fixture.showPanelWithACleanAnchor()

        // Left where it was created, which is far enough from the panel's anchor to arm the
        // gesture if `windowDidMove` did not check which window actually moved.
        let other = fixture.makeStandInWindow()
        try #require(
            manager.panelDragDistance(of: other) > AppConstants.Window.dragToPinThreshold,
            "This window has to be past the threshold for the identity guard to be under test")

        manager.windowDidMove(fixture.moveNotification(for: other))

        #expect(manager.isAwaitingDragToPinRelease == false)
    }
}
