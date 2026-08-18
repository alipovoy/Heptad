import AppKit
import Carbon.HIToolbox

/// Owns the system-wide hotkey that summons and dismisses the app.
///
/// Deliberately built on Carbon's `RegisterEventHotKey` rather than
/// `NSEvent.addGlobalMonitorForEvents`: the Carbon API works inside the App Sandbox and
/// needs no Accessibility permission, so the app never has to ask the user for one.
///
/// The manager knows nothing about windows — it just calls `onHotKey`.
@MainActor
class GlobalHotKeyManager {
    /// Invoked every time the registered hotkey is pressed, on the main thread.
    var onHotKey: (() -> Void)?

    // The four constants below are `nonisolated`: they are immutable values, and the Carbon
    // callback at the bottom of this file reads two of them from a C function pointer, which
    // has no isolation to inherit. Left isolated with the rest of the class, that read is a
    // warning today and an error under the Swift 6 language mode.

    /// Default binding: ⌃⌥Space.
    nonisolated static let defaultKeyCode = UInt32(kVK_Space)
    nonisolated static let defaultModifierFlags: NSEvent.ModifierFlags = [.control, .option]

    /// Four-char code 'Hept', marking hotkey events as belonging to this app.
    nonisolated static let signature = OSType(0x4865_7074)

    /// Only one hotkey is registered, so a fixed id is enough to identify it.
    nonisolated static let hotKeyIdentifier: UInt32 = 1

    private let defaults: UserDefaults

    /// The two Carbon handles, `nonisolated(unsafe)` so `deinit` can release them.
    ///
    /// They are `OpaquePointer`s and so not Sendable, which under the Swift 6 language mode
    /// puts them out of reach of a nonisolated `deinit` — and `deinit` is where the teardown
    /// has to happen. The exemption is narrow: every other access is through the isolated
    /// methods below, and by `deinit` no other reference to this object exists, so there is
    /// nothing left for the isolation to serialise against.
    nonisolated(unsafe) private var hotKeyRef: EventHotKeyRef?
    nonisolated(unsafe) private var eventHandler: EventHandlerRef?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The teardown, inlined for the same reason as `EventMonitor`'s: a nonisolated `deinit`
    /// cannot call the isolated `unregister()`, and `isolated deinit` is not safe to ship at
    /// this project's macOS 14 target. See the note there, and #88.
    ///
    /// Both calls are plain C and carry no isolation of their own, and by `deinit` nothing
    /// else holds these refs.
    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    // MARK: - Binding

    /// True while the hotkey is claimed from the system.
    var isRegistered: Bool { hotKeyRef != nil }

    /// Virtual keycode (a `kVK_*` value) of the current binding.
    var keyCode: UInt32 {
        guard let stored = defaults.object(forKey: AppConstants.globalHotKeyKeyCodeKey) as? Int,
            (0...0xFFFF).contains(stored)
        else { return Self.defaultKeyCode }
        return UInt32(stored)
    }

    /// Modifiers of the current binding.
    ///
    /// Persisted as a Cocoa `NSEvent.ModifierFlags` raw value — the representation a future
    /// key-recorder UI would hand us straight from an `NSEvent` — and translated into
    /// Carbon's unrelated modifier bits only at registration time.
    var modifierFlags: NSEvent.ModifierFlags {
        guard
            let stored = defaults.object(forKey: AppConstants.globalHotKeyModifierFlagsKey) as? Int,
            stored >= 0
        else { return Self.defaultModifierFlags }
        return NSEvent.ModifierFlags(rawValue: UInt(stored))
            .intersection(.deviceIndependentFlagsMask)
    }

    /// The current binding written the way a menu shows it — `⌃⌥Space`.
    ///
    /// Built from what is stored rather than spelled out at the call site, so the one place the app
    /// can say the summon key is unavailable cannot name a combination the user is not bound to.
    /// Glyph order is Apple's own: control, option, shift, command.
    var bindingDescription: String {
        let flags = modifierFlags
        let glyphs = [
            (NSEvent.ModifierFlags.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")
        ]

        return glyphs.reduce(into: "") { description, glyph in
            if flags.contains(glyph.0) { description += glyph.1 }
        } + Self.name(of: keyCode)
    }

    /// A key as that description names it: Space by name, anything the machine's Latin layout types
    /// by its own character, and otherwise the number.
    ///
    /// The number is deliberate rather than a table of every function and arrow key: a binding this
    /// cannot name is one no UI offers yet, and a wrong name would be worse than a plain one.
    private static func name(of keyCode: UInt32) -> String {
        guard keyCode != UInt32(kVK_Space) else { return "Space" }

        let typed = KeyboardLayout.asciiCharacter(forKeyCode: UInt16(keyCode)) ?? ""
        guard let scalar = typed.unicodeScalars.first, (0x21...0x7E).contains(scalar.value) else {
            return "key \(keyCode)"
        }

        return typed.uppercased()
    }

    /// Persists a new binding, and answers whether the system will actually give it to us.
    /// There is no settings UI yet; this is the seam one would drive.
    ///
    /// A binding that will not register is rolled back and the working one reclaimed: `register()`
    /// gives up its claim before it tries, so a combination another app owns would otherwise be
    /// left in `UserDefaults` and leave the app with no hotkey at all, at this launch and every
    /// one after.
    ///
    /// Tried whether or not the hotkey is currently live, because "not live" is exactly the state
    /// launch registration leaves behind when the combination was already owned — the one case
    /// where an unchecked write would stick.
    ///
    /// A combination the system grants is left claimed, from either state. Handing the claim back
    /// when there was none to begin with would keep the answer honest and the hotkey dead: a user
    /// rebinding after a lost launch race would be told the new combination is theirs and still have
    /// no summon key until the next launch, which is the state they were escaping.
    @discardableResult
    func setBinding(keyCode: UInt32, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        let previous = (keyCode: self.keyCode, modifierFlags: self.modifierFlags)
        let wasRegistered = isRegistered
        store(keyCode: keyCode, modifierFlags: modifierFlags)

        if register() { return true }

        store(keyCode: previous.keyCode, modifierFlags: previous.modifierFlags)
        if wasRegistered { register() }
        return false
    }

    private func store(keyCode: UInt32, modifierFlags: NSEvent.ModifierFlags) {
        let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        defaults.set(Int(keyCode), forKey: AppConstants.globalHotKeyKeyCodeKey)
        defaults.set(Int(flags.rawValue), forKey: AppConstants.globalHotKeyModifierFlagsKey)
    }

    /// Carbon's modifier constants are a bit set of their own, unrelated to `NSEvent.ModifierFlags`.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }

    // MARK: - Registration

    /// Installs the Carbon event handler and claims the hotkey. Safe to call repeatedly:
    /// any previous registration is torn down first.
    ///
    /// Returns false when the combination is unavailable — most often another app already
    /// owns it. That is not fatal: everything else keeps working, only the hotkey is inert.
    @discardableResult
    func register() -> Bool {
        unregister()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed))

        // Passed unretained: the handler is removed in unregister() and deinit, so it can
        // never outlive this object and the pointer can never dangle.
        let context = Unmanaged.passUnretained(self).toOpaque()

        let installStatus = InstallEventHandler(
            GetEventDispatcherTarget(), hotKeyEventHandler, 1, &eventType, context, &eventHandler)
        guard installStatus == noErr else {
            eventHandler = nil
            return false
        }

        var ref: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: Self.signature, id: Self.hotKeyIdentifier)
        let registerStatus = RegisterEventHotKey(
            keyCode, Self.carbonModifiers(from: modifierFlags), identifier,
            GetEventDispatcherTarget(), 0, &ref)

        guard registerStatus == noErr, let ref else {
            unregister()
            return false
        }

        hotKeyRef = ref
        return true
    }

    /// Releases the hotkey and the event handler. Idempotent.
    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }
}

/// C entry point for `kEventHotKeyPressed`. A C function pointer cannot capture Swift
/// context, so the manager travels through Carbon's `userData` pointer instead.
private func hotKeyEventHandler(
    _ callRef: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    var identifier = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
        nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)

    guard status == noErr,
        identifier.signature == GlobalHotKeyManager.signature,
        identifier.id == GlobalHotKeyManager.hotKeyIdentifier
    else { return OSStatus(eventNotHandledErr) }

    // Carbon dispatches hotkey events through the main run loop, so this is the main thread.
    // assumeIsolated encodes that guarantee for the compiler instead of leaving it a comment:
    // the handler ends up touching AppKit, and a debug build now traps if it ever runs elsewhere.
    let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated {
        manager.onHotKey?()
    }
    return noErr
}
