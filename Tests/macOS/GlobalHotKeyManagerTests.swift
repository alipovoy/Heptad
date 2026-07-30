import Carbon.HIToolbox
import XCTest

@testable import Heptad

final class GlobalHotKeyManagerTests: XCTestCase {
    private var suiteName: String = ""
    private var defaults: UserDefaults!

    /// An unlikely-to-be-taken combination, so registration tests don't collide with
    /// whatever the developer's machine already has bound.
    private let spareKeyCode = UInt32(kVK_F16)
    private let spareModifiers: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "GlobalHotKeyManagerTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - Defaults

    func testDefaultBindingIsControlOptionSpace() {
        let manager = GlobalHotKeyManager(defaults: defaults)

        XCTAssertEqual(manager.keyCode, UInt32(kVK_Space), "Default keycode should be Space (49)")
        XCTAssertEqual(manager.modifierFlags, [.control, .option], "Default modifiers should be ⌃⌥")
    }

    func testOutOfRangeStoredValuesFallBackToDefaults() {
        defaults.set(-1, forKey: AppConstants.globalHotKeyKeyCodeKey)
        defaults.set(-1, forKey: AppConstants.globalHotKeyModifierFlagsKey)

        let manager = GlobalHotKeyManager(defaults: defaults)

        XCTAssertEqual(manager.keyCode, GlobalHotKeyManager.defaultKeyCode)
        XCTAssertEqual(manager.modifierFlags, GlobalHotKeyManager.defaultModifierFlags)
    }

    func testNonNumericStoredValuesFallBackToDefaults() {
        defaults.set("not a keycode", forKey: AppConstants.globalHotKeyKeyCodeKey)
        defaults.set("not a modifier", forKey: AppConstants.globalHotKeyModifierFlagsKey)

        let manager = GlobalHotKeyManager(defaults: defaults)

        XCTAssertEqual(manager.keyCode, GlobalHotKeyManager.defaultKeyCode)
        XCTAssertEqual(manager.modifierFlags, GlobalHotKeyManager.defaultModifierFlags)
    }

    // MARK: - Persistence

    func testBindingRoundTripsThroughUserDefaults() {
        GlobalHotKeyManager(defaults: defaults)
            .setBinding(keyCode: UInt32(kVK_ANSI_J), modifierFlags: [.command, .shift])

        // A fresh manager stands in for the next app launch.
        let relaunched = GlobalHotKeyManager(defaults: defaults)

        XCTAssertEqual(relaunched.keyCode, UInt32(kVK_ANSI_J))
        XCTAssertEqual(relaunched.modifierFlags, [.command, .shift])
    }

    func testBindingStripsDeviceDependentModifierBits() {
        let manager = GlobalHotKeyManager(defaults: defaults)
        // .init(rawValue: 1) is the device-dependent left-shift bit; it must not survive.
        manager.setBinding(
            keyCode: UInt32(kVK_ANSI_K),
            modifierFlags: [.control, NSEvent.ModifierFlags(rawValue: 1)])

        XCTAssertEqual(manager.modifierFlags, [.control])
    }

    // MARK: - Carbon modifier conversion

    func testCarbonModifierConversion() {
        XCTAssertEqual(GlobalHotKeyManager.carbonModifiers(from: []), 0)
        XCTAssertEqual(
            GlobalHotKeyManager.carbonModifiers(from: .command), UInt32(cmdKey))
        XCTAssertEqual(
            GlobalHotKeyManager.carbonModifiers(from: .option), UInt32(optionKey))
        XCTAssertEqual(
            GlobalHotKeyManager.carbonModifiers(from: .control), UInt32(controlKey))
        XCTAssertEqual(
            GlobalHotKeyManager.carbonModifiers(from: .shift), UInt32(shiftKey))
        XCTAssertEqual(
            GlobalHotKeyManager.carbonModifiers(from: [.control, .option]),
            UInt32(controlKey) | UInt32(optionKey),
            "⌃⌥ must map onto Carbon's own bit set, not NSEvent's")
        // Modifiers Carbon has no bit for are simply dropped rather than corrupting the mask.
        XCTAssertEqual(GlobalHotKeyManager.carbonModifiers(from: .function), 0)
    }

    // MARK: - Registration lifecycle

    func testRegisterThenUnregister() {
        let manager = GlobalHotKeyManager(defaults: defaults)
        manager.setBinding(keyCode: spareKeyCode, modifierFlags: spareModifiers)

        XCTAssertFalse(manager.isRegistered, "Should start unregistered")
        XCTAssertTrue(manager.register(), "Registering a free combination should succeed")
        XCTAssertTrue(manager.isRegistered)

        manager.unregister()
        XCTAssertFalse(manager.isRegistered)
    }

    func testDoubleRegisterAndDoubleUnregisterAreSafe() {
        let manager = GlobalHotKeyManager(defaults: defaults)
        manager.setBinding(keyCode: spareKeyCode, modifierFlags: spareModifiers)

        XCTAssertTrue(manager.register())
        // The second call must tear the first registration down rather than stack on it.
        XCTAssertTrue(manager.register(), "Re-registering should replace, not fail")
        XCTAssertTrue(manager.isRegistered)

        manager.unregister()
        manager.unregister()
        XCTAssertFalse(manager.isRegistered)
    }

    func testUnregisterBeforeRegisterIsSafe() {
        let manager = GlobalHotKeyManager(defaults: defaults)
        manager.unregister()
        XCTAssertFalse(manager.isRegistered)
    }

    func testChangingBindingWhileRegisteredStaysRegistered() {
        let manager = GlobalHotKeyManager(defaults: defaults)
        manager.setBinding(keyCode: spareKeyCode, modifierFlags: spareModifiers)
        XCTAssertTrue(manager.register())

        XCTAssertTrue(manager.setBinding(keyCode: UInt32(kVK_F17), modifierFlags: spareModifiers))
        XCTAssertTrue(manager.isRegistered)
        XCTAssertEqual(manager.keyCode, UInt32(kVK_F17))

        manager.unregister()
    }

    func testDeallocatingARegisteredManagerReleasesTheHotKey() {
        var manager: GlobalHotKeyManager? = GlobalHotKeyManager(defaults: defaults)
        manager?.setBinding(keyCode: spareKeyCode, modifierFlags: spareModifiers)
        XCTAssertEqual(manager?.register(), true)

        // deinit must unregister; otherwise the combination stays claimed process-wide and
        // this second registration would fail.
        manager = nil

        let successor = GlobalHotKeyManager(defaults: defaults)
        XCTAssertTrue(successor.register(), "deinit should have released the hotkey")
        successor.unregister()
    }
}
