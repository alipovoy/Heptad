import AppKit
import Testing

@testable import Heptad

/// Who owns activation once the window goes away.
///
/// Ordering the window out is not enough: Heptad is an accessory app, so AppKit leaves it the
/// *active* application with nothing on screen, and the app underneath is drawn frontmost without
/// ever being told to restore its first responder. Every test here is about naming the successor.
@MainActor
@Suite(.serialized, .tags(.windowServer))
struct WindowActivationTests {
    private let fixture: WindowManagerFixture
    private var manager: WindowManager { fixture.manager }
    private var activation: SpyActivationCoordinator { fixture.activation }

    init() throws {
        fixture = try WindowManagerFixture()
    }

    @Test(.requiresAnotherRunningApp)
    func closingHandsActivationBackToTheAppThatHadIt() throws {
        let previous = try fixture.otherRunningApplication()
        fixture.postActivation(of: previous)

        let window = try fixture.showWindow()
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
    func showingFallsBackToTheFrontmostAppWhenNoActivationWasObserved() throws {
        // An app that was already frontmost when Heptad launched never posts an activation.
        let previous = try fixture.otherRunningApplication()
        activation.frontmostApplication = previous

        let window = try fixture.showWindow()
        _ = manager.windowShouldClose(window)

        #expect(activation.activatedApps.last == previous)
    }

    @Test func closingWithNoKnownPreviousAppJustGivesUpActiveStatus() throws {
        let window = try fixture.showWindow()

        _ = manager.windowShouldClose(window)

        #expect(activation.activatedApps.isEmpty, "There is no app to hand activation to")
        #expect(activation.deactivatedCurrentAppCount == 1)
    }

    @Test(.requiresAnotherRunningApp)
    func closingLeavesActivationAloneWhenAnotherAppAlreadyHasIt() throws {
        fixture.postActivation(of: try fixture.otherRunningApplication())
        let window = try fixture.showWindow()

        // What a click outside the panel looks like: the click already activated the other app.
        activation.isCurrentAppActive = false
        _ = manager.windowShouldClose(window)

        #expect(activation.activatedApps.isEmpty, "Must not steal focus back from the click")
        #expect(activation.deactivatedCurrentAppCount == 0)
    }

    @Test func heptadItselfIsNeverRecordedAsThePreviousApp() throws {
        fixture.postActivation(of: .current)
        let window = try fixture.showWindow()

        _ = manager.windowShouldClose(window)

        #expect(activation.activatedApps.isEmpty, "Reactivating Heptad would be a no-op loop")
        #expect(activation.deactivatedCurrentAppCount == 1)
    }
}
