import AppKit
import Carbon.HIToolbox
import Testing

@testable import Heptad

/// An unlikely-to-be-taken combination, so registration tests don't collide with
/// whatever the developer's machine already has bound.
private let spareKeyCode = UInt32(kVK_F16)
/// The second binding `changingBindingWhileRegisteredStaysRegistered` switches to.
private let spareSuccessorKeyCode = UInt32(kVK_F17)
private let spareModifiers: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

/// Spelled out as a typed constant rather than inline: as a literal in the `arguments:` list it
/// is a heterogeneous option-set expression the type checker gives up on.
private let carbonModifierCases: [(NSEvent.ModifierFlags, UInt32)] = [
    ([], 0),
    (.command, UInt32(cmdKey)),
    (.option, UInt32(optionKey)),
    (.control, UInt32(controlKey)),
    (.shift, UInt32(shiftKey)),
    // ⌃⌥ must map onto Carbon's own bit set, not NSEvent's.
    ([.control, .option], UInt32(controlKey) | UInt32(optionKey)),
    // Modifiers Carbon has no bit for are dropped rather than corrupting the mask.
    (.function, 0)
]

/// The two junk shapes a stored keycode/modifier pair can take: a numeric value out of Carbon's
/// range, or a value that isn't numeric at all. Both have to fall back to the defaults the same
/// way, which is what lets one parameterized test stand in for what used to be two near-identical
/// ones.
enum JunkDefaultsValue: Sendable, CustomTestStringConvertible {
    case outOfRange
    case nonNumeric

    var testDescription: String {
        switch self {
        case .outOfRange: return "out of range"
        case .nonNumeric: return "non-numeric"
        }
    }

    func apply(to defaults: UserDefaults) {
        switch self {
        case .outOfRange:
            defaults.set(-1, forKey: AppConstants.globalHotKeyKeyCodeKey)
            defaults.set(-1, forKey: AppConstants.globalHotKeyModifierFlagsKey)
        case .nonNumeric:
            defaults.set("not a keycode", forKey: AppConstants.globalHotKeyKeyCodeKey)
            defaults.set("not a modifier", forKey: AppConstants.globalHotKeyModifierFlagsKey)
        }
    }
}

/// Claims `keyCode` with the spare modifiers and releases it again, so "the manager is broken"
/// can be told apart from "something else on this machine already owns that combination".
@MainActor
private func spareCombinationIsAvailable(keyCode: UInt32) -> Bool {
    let suiteName = "GlobalHotKeyManagerTests.probe.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else { return false }
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let probe = GlobalHotKeyManager(defaults: defaults)
    probe.setBinding(keyCode: keyCode, modifierFlags: spareModifiers)
    guard probe.register() else { return false }
    probe.unregister()
    return true
}

extension Trait where Self == ConditionTrait {
    /// Guards the tests that assert `register()` succeeds.
    ///
    /// A hotkey is claimed process-wide from the window server, so registration fails whenever
    /// another running app already owns the combination. That is a fact about the machine and
    /// says nothing about `GlobalHotKeyManager`, so its absence skips the test instead of
    /// failing it with no hint as to why.
    fileprivate static var requiresTheSpareCombination: Self {
        .enabled("⌃⌥⇧⌘F16/F17 is already claimed on this machine") {
            await MainActor.run {
                spareCombinationIsAvailable(keyCode: spareKeyCode)
                    && spareCombinationIsAvailable(keyCode: spareSuccessorKeyCode)
            }
        }
    }
}

/// A registered hotkey is claimed from the system for the whole process, and three tests below
/// claim the same spare combination — so they run one at a time rather than racing each other
/// for it. `@MainActor` on top: Carbon's event dispatcher target is the main run loop's.
@MainActor
@Suite(.serialized, .tags(.systemResource))
struct GlobalHotKeyManagerTests {
    private let scratchDefaults: ScratchDefaults
    private var defaults: UserDefaults { scratchDefaults.defaults }

    init() throws {
        scratchDefaults = try ScratchDefaults(name: "GlobalHotKeyManagerTests")
    }

    // MARK: - Defaults

    @Test func defaultBindingIsControlOptionSpace() {
        let manager = GlobalHotKeyManager(defaults: defaults)

        #expect(manager.keyCode == UInt32(kVK_Space), "Default keycode should be Space (49)")
        #expect(manager.modifierFlags == [.control, .option], "Default modifiers should be ⌃⌥")
    }

    /// Junk in the stored keycode/modifier keys — out of range or not even numeric — has to
    /// fall back to the defaults rather than propagate, since either would eventually reach
    /// Carbon as a registration request.
    @Test(arguments: [JunkDefaultsValue.outOfRange, .nonNumeric])
    func junkStoredValuesFallBackToDefaults(junk: JunkDefaultsValue) {
        junk.apply(to: defaults)

        let manager = GlobalHotKeyManager(defaults: defaults)

        #expect(manager.keyCode == GlobalHotKeyManager.defaultKeyCode)
        #expect(manager.modifierFlags == GlobalHotKeyManager.defaultModifierFlags)
    }

    // MARK: - Persistence

    @Test func bindingRoundTripsThroughUserDefaults() {
        GlobalHotKeyManager(defaults: defaults)
            .setBinding(keyCode: UInt32(kVK_ANSI_J), modifierFlags: [.command, .shift])

        // A fresh manager stands in for the next app launch.
        let relaunched = GlobalHotKeyManager(defaults: defaults)

        #expect(relaunched.keyCode == UInt32(kVK_ANSI_J))
        #expect(relaunched.modifierFlags == [.command, .shift])
    }

    @Test func bindingStripsDeviceDependentModifierBits() {
        let manager = GlobalHotKeyManager(defaults: defaults)
        // .init(rawValue: 1) is the device-dependent left-shift bit; it must not survive.
        manager.setBinding(
            keyCode: UInt32(kVK_ANSI_K),
            modifierFlags: [.control, NSEvent.ModifierFlags(rawValue: 1)])

        #expect(manager.modifierFlags == [.control])
    }

    // MARK: - Carbon modifier conversion

    @Test(arguments: carbonModifierCases)
    func carbonModifierConversion(flags: NSEvent.ModifierFlags, carbon: UInt32) {
        #expect(GlobalHotKeyManager.carbonModifiers(from: flags) == carbon)
    }

    // MARK: - Registration lifecycle

    /// Registering and unregistering, including calling either twice in a row: a fresh manager
    /// starts unregistered, `register()` claims the combination, a second `register()` must
    /// tear the first claim down rather than stack on it, and `unregister()` is safe to call
    /// more than once.
    @Test(.requiresTheSpareCombination)
    func doubleRegisterAndDoubleUnregisterAreSafe() {
        let manager = GlobalHotKeyManager(defaults: defaults)
        manager.setBinding(keyCode: spareKeyCode, modifierFlags: spareModifiers)

        #expect(manager.isRegistered == false, "Should start unregistered")
        #expect(manager.register(), "Registering a free combination should succeed")
        // The second call must tear the first registration down rather than stack on it.
        #expect(manager.register(), "Re-registering should replace, not fail")
        #expect(manager.isRegistered)

        manager.unregister()
        manager.unregister()
        #expect(manager.isRegistered == false)
    }

    @Test func unregisterBeforeRegisterIsSafe() {
        let manager = GlobalHotKeyManager(defaults: defaults)
        manager.unregister()
        #expect(manager.isRegistered == false)
    }

    @Test(.requiresTheSpareCombination)
    func changingBindingWhileRegisteredStaysRegistered() {
        let manager = GlobalHotKeyManager(defaults: defaults)
        manager.setBinding(keyCode: spareKeyCode, modifierFlags: spareModifiers)
        #expect(manager.register())

        #expect(manager.setBinding(keyCode: spareSuccessorKeyCode, modifierFlags: spareModifiers))
        #expect(manager.isRegistered)
        #expect(manager.keyCode == spareSuccessorKeyCode)

        manager.unregister()
    }

    @Test(.requiresTheSpareCombination)
    func deallocatingARegisteredManagerReleasesTheHotKey() {
        var manager: GlobalHotKeyManager? = GlobalHotKeyManager(defaults: defaults)
        manager?.setBinding(keyCode: spareKeyCode, modifierFlags: spareModifiers)
        #expect(manager?.register() == true)

        // deinit must unregister; otherwise the combination stays claimed process-wide and
        // this second registration would fail.
        manager = nil

        let successor = GlobalHotKeyManager(defaults: defaults)
        #expect(successor.register(), "deinit should have released the hotkey")
        successor.unregister()
    }
}
