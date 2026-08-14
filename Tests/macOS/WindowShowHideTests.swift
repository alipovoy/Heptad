import AppKit
import Testing

@testable import Heptad

/// What the window announces as it comes and goes, and what a toggle does to a pinned window that
/// is already on screen.
///
/// Hiding orders the window out instead of tearing it down, so the hosted `ContentView` is never
/// unmounted and hears nothing from SwiftUI. These notifications are its only signal, and the
/// relative-time ticker is switched off by them.
///
/// The third hide path — the click-outside monitor — is driven by a global `NSEvent` monitor that
/// only the window server can fire, so what is tested is the decision it makes about one event:
/// `handleClickOutside(_:)` is handed a synthesized click rather than a real one.
///
/// Both tests that depend on real key-window status live here rather than being spread across
/// suites: `.serialized` then guarantees they cannot race each other for it.
@MainActor
@Suite(.serialized, .tags(.windowServer))
struct WindowShowHideTests {
    private let fixture: WindowManagerFixture
    private var manager: WindowManager { fixture.manager }

    init() throws {
        fixture = try WindowManagerFixture()
    }

    // MARK: - Pinned show/hide
    //
    // A pinned window is neither re-anchored nor dismissed by a click outside, so the menubar
    // icon (and the global hotkey, which lands in the same place) is its show/hide control.

    @Test(.bug(id: 59))
    func togglingAPinnedWindowThatIsAlreadyKeyHidesIt() async throws {
        let window = try fixture.showWindow()
        manager.setPinned(true)

        // The test host has to be the active app first (#127). The window used to carry
        // `.nonactivatingPanel`, which is what let it take key status in a background process;
        // without it the window server grants key only to the active application, and
        // `makeKeyAndOrderFront` alone waits forever. The real app has the same dependency —
        // `showWindow` calls `takeActivation()` — but that goes through the spy here, which
        // records the call rather than performing it.
        NSApp.activate(ignoringOtherApps: true)

        // Key status is granted by the window server rather than set, so it is waited for.
        window.makeKeyAndOrderFront(nil)
        try await waitUntil("the pinned window to become key") { window.isKeyWindow }

        manager.toggleWindow(sender: fixture.statusBarButton)

        #expect(window.isVisible == false, "A pinned window already in front hides on toggle")
        #expect(manager.isPanelMode, "and comes back as the menubar panel — see #123")
    }

    // MARK: - The click-outside monitor

    /// A click carrying one of this app's own windows is a click *inside* it.
    ///
    /// The monitor is global, and a global monitor is documented to see only what is dispatched
    /// to other applications — but not the click that activates an inactive app, which arrives
    /// here too with `event.window` resolved in this process. Heptad is inactive on every show
    /// that follows a dismissal, so the first click after one was closing the panel: any click,
    /// the text included, and the note went away under the caret.
    @Test func aClickCarryingOneOfOurOwnWindowsDoesNotDismissThePanel() throws {
        let window = try fixture.showWindow()

        manager.handleClickOutside(try click(in: window))

        #expect(window.isVisible, "The activation click landed in the window, not outside it")
    }

    @Test func aClickInAnotherApplicationDismissesThePanel() throws {
        let window = try fixture.showWindow()

        manager.handleClickOutside(try click(in: nil))

        #expect(window.isVisible == false)
        #expect(manager.isPanelMode, "and it comes back as the panel — see #123")
    }

    /// A pinned window is not dismissed by a click outside it at all.
    @Test func aClickOutsideAPinnedWindowLeavesItAlone() throws {
        let window = try fixture.showWindow()
        manager.setPinned(true)

        manager.handleClickOutside(try click(in: nil))

        #expect(window.isVisible)
    }

    /// A left mouse-down as the monitor reports it. `windowNumber` is the whole subject: it is
    /// what `NSEvent.window` resolves from, and 0 is what a click in another process carries.
    private func click(in window: NSWindow?) throws -> NSEvent {
        try #require(
            NSEvent.mouseEvent(
                with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window?.windowNumber ?? 0, context: nil, eventNumber: 0,
                clickCount: 1, pressure: 1))
    }

    // MARK: - Flushing pending saves

    @Test func showingTheWindowDoesNotFlush() async throws {
        try await fixture.expectingNotification(.flushPendingSaves, count: 0) {
            _ = try fixture.showWindow()
        }
    }

    // MARK: - Hiding the window

    /// Which call routes into the shared `hide(window:)`.
    enum HideTrigger {
        case toggleWindowToClose
        case windowShouldClose
    }

    /// `toggleWindow`'s hide branch and `windowShouldClose` both end at the same private
    /// `hide(window:)`, so a regression that made one of them skip the flush or forget to
    /// announce the hide would only surface if the other path happened to be exercised too.
    /// Driving both entry points against both notifications here catches that drift directly
    /// instead of by whichever caller a future test happens to add coverage through.
    @Test(arguments: [HideTrigger.toggleWindowToClose, .windowShouldClose])
    func hidingTheWindowFlushesSavesAndAnnouncesTheHide(via trigger: HideTrigger) async throws {
        let window = try fixture.showWindow()

        try await fixture.expectingFlushAndHide {
            switch trigger {
            case .toggleWindowToClose:
                manager.toggleWindow(sender: fixture.statusBarButton)
            case .windowShouldClose:
                _ = manager.windowShouldClose(window)
            }
        }
    }

    // MARK: - Visibility

    @Test func showingTheWindowAnnouncesItIsVisible() async throws {
        try await fixture.expectingNotification(.windowDidBecomeVisible) {
            _ = try fixture.showWindow()
        }
    }

    /// Raising a pinned window that another app is covering pins two effects of one
    /// `toggleWindow` call: it must activate Heptad, or typing would go to the wrong app, and it
    /// must NOT re-announce `.windowDidBecomeVisible` — the window was on screen throughout, and
    /// announcing a show would restart a ticker that is already running. Both assertions drive
    /// the same "covered pinned window" fixture, so splitting them apart would only pay for that
    /// fixture twice; losing either half here would let a regression through that stops the raise
    /// from activating, or makes it restart the ticker every time focus comes back to it.
    @Test(.bug(id: 59))
    func raisingACoveredPinnedWindowActivatesButAnnouncesNothing() async throws {
        let window = try fixture.showWindow()
        manager.setPinned(true)
        let activationsBefore = fixture.activation.activatedCurrentAppCount

        // Stands in for another app's window covering the pinned one: key status sits elsewhere.
        let cover = fixture.makeStandInWindow()
        cover.makeKeyAndOrderFront(nil)
        try #require(window.isKeyWindow == false, "The pinned window must not be the key window")

        await fixture.expectingNotification(.windowDidBecomeVisible, count: 0) {
            manager.toggleWindow(sender: fixture.statusBarButton)
        }

        #expect(window.isVisible, "A covered pinned window is raised, not hidden")
        #expect(
            fixture.activation.activatedCurrentAppCount == activationsBefore + 1,
            "Raising the window is useless without activation — typing would go elsewhere")
    }
}
