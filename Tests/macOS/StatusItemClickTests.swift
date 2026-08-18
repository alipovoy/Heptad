import AppKit
import Testing

@testable import Heptad

/// Which status-item clicks open the menu rather than the panel. The menu is the app's only
/// chrome, and its Quit item the only way out other than ⌘Q. What each branch then does — a menu
/// popping up, a window appearing — is not assertable in a test host; the decision is.
@MainActor
struct StatusItemClickTests {

    private func click(
        _ type: NSEvent.EventType, _ flags: NSEvent.ModifierFlags = []
    ) throws -> NSEvent {
        try #require(
            NSEvent.mouseEvent(
                with: type, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }

    @Test func aRightClickOpensTheMenu() throws {
        #expect(AppDelegate().isSecondaryClick(try click(.rightMouseUp)))
    }

    /// ⌃-click is the documented equivalent of a right-click on macOS, and it arrives as a
    /// `.leftMouseUp` carrying `.control` — which used to fall through to the panel.
    @Test func aControlClickOpensTheMenu() throws {
        #expect(AppDelegate().isSecondaryClick(try click(.leftMouseUp, .control)))
    }

    /// Every other modifier is still a plain click: ⌥, ⌘ and ⇧ mean nothing on this icon, and
    /// swallowing them into the menu would take the panel away from a mistimed keypress.
    @Test(arguments: [NSEvent.ModifierFlags.option, .command, .shift, []])
    func anyOtherLeftClickOpensThePanel(flags: NSEvent.ModifierFlags) throws {
        #expect(!AppDelegate().isSecondaryClick(try click(.leftMouseUp, flags)))
    }

    /// VoiceOver and UI automation send the action with no event behind it. That is a plain
    /// activation, not a menu request.
    @Test func anActionWithNoEventOpensThePanel() {
        #expect(!AppDelegate().isSecondaryClick(nil))
    }
}
