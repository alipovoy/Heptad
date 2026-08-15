import AppKit
import Carbon.HIToolbox

/// Which character the shortcut tables should match a ⌘ keystroke on.
///
/// `NSEvent.charactersIgnoringModifiers` reports what the *current* layout types, so on a Cyrillic
/// layout ⌘B arrives as "и" and every case in `EditorShortcutManager`'s tables misses. What the
/// user got instead was the app's shortcuts doing nothing and ⌘C/⌘V/⌘X still working — those are
/// AppKit's own key equivalents, and AppKit falls back to an ASCII-capable layout when the current
/// one produces no ASCII. A raw event monitor gets no such service, so ⌘V fell through to
/// `NSTextView.paste` (the #117 path) and ⌘⇧V to `pasteAsPlainText` (the #114 path).
///
/// This performs that same fallback, in that same order — and the order is the whole design.
/// Matching on `event.keyCode` alone would be simpler and wrong: virtual keycodes are *positions*,
/// so the key labelled A on a French AZERTY keyboard is `kVK_ANSI_Q`, and ⌘A over a note's text
/// would quit the app. The layout's own character has to win wherever it is Latin.
enum KeyboardLayout {

    /// The character `event` should be dispatched on: what it typed, when that is ASCII, and
    /// otherwise the Latin character sitting on the same physical key.
    ///
    /// Lowercased, because shift is read separately by every case that cares — which is what lets
    /// the tables spell ⌘⇧V as `"v" where hasShift` and drop the duplicate `"V"` beside it.
    ///
    /// `asciiCharacter` is injected so the fallback's *ordering* can be tested without an input
    /// source to install: the shipping translation depends on which layouts the machine has.
    static func commandKey(
        for event: NSEvent,
        asciiCharacter: (UInt16) -> String? = Self.asciiCharacter(forKeyCode:)
    ) -> String {
        let typed = (event.charactersIgnoringModifiers ?? "").lowercased()

        // A Latin layout's own character wins: on Dvorak ⌘C belongs where Dvorak puts "c", and on
        // AZERTY the key labelled A is ⌘A rather than the ⌘Q its keycode would claim. This is also
        // why the translation below costs nothing on a Latin layout — it never runs.
        if !typed.isEmpty, typed.allSatisfy(\.isASCII) { return typed }

        // Falling back to `typed` keeps a non-Latin keystroke matching nothing, as it does today,
        // rather than matching something else.
        return asciiCharacter(event.keyCode)?.lowercased() ?? typed
    }

    /// What `keyCode` would type on the machine's ASCII-capable layout, unshifted — nil when there
    /// is no such layout or the key produces nothing on it.
    ///
    /// macOS guarantees an ASCII-capable input source exists, so in practice this is the user's
    /// Latin layout: the one they switch to to type an English word.
    static func asciiCharacter(forKeyCode keyCode: UInt16) -> String? {
        guard
            let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
            let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data

        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)

        // Modifier state 0 — the unshifted character, so this never has to agree with the tables
        // about what shift means.
        let status = data.withUnsafeBytes { bytes -> OSStatus in
            guard let layout = bytes.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self)
            else { return -1 }

            return UCKeyTranslate(
                layout, keyCode, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState, characters.count,
                &length, &characters)
        }

        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }
}
