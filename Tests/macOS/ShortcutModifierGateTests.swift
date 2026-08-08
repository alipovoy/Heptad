import AppKit
import Testing

@testable import Heptad

/// What reaches either of `EditorShortcutManager`'s dispatch tables at all.
///
/// In the app this is the first thing the key monitor applies; it sits outside the monitor
/// closure so it can be asserted here. `EditorShortcutManagerTests` covers what the tables do
/// with the events that get through.
@MainActor
struct ShortcutModifierGateTests {

    @Test(
        arguments: [
            (NSEvent.ModifierFlags.command, true),
            ([.command, .shift], true),
            // Held but irrelevant: the gate excludes option and control and nothing else.
            ([.command, .capsLock], true),
            ([.command, .function], true),
            // ⌥⌘B and ⌃⌘B both report "b", so admitting either would toggle bold.
            ([.command, .option], false),
            ([.command, .control], false),
            ([.command, .option, .control], false),
            // No ⌘ at all: ordinary typing, which the app never claims.
            ([.shift], false),
            ([], false)
        ] as [(NSEvent.ModifierFlags, Bool)])
    func theGateAdmitsCommandWithoutOptionOrControl(
        flags: NSEvent.ModifierFlags, admitted: Bool
    ) {
        #expect(EditorShortcutManager.handlesModifiers(flags) == admitted)
    }
}
