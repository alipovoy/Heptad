import AppKit
import Carbon.HIToolbox
import Testing

@testable import Heptad

/// Which character a ⌘ keystroke is dispatched on, layout by layout.
///
/// `NSEvent.keyEvent` takes `charactersIgnoringModifiers` and `keyCode` as separate arguments, so
/// every layout below is synthesized here rather than installed as an input source.
///
/// The fallback is injected in most of these, because the shipping translation reads whichever
/// layouts the machine happens to have. `theMachinesOwnLayoutTranslatesTheAlphabet` uses the real
/// one once, and skips where it does not hold.
@Suite struct KeyboardLayoutTests {

    /// One keystroke and the character the shortcut tables must see for it.
    struct Keystroke: Sendable {
        let typed: String
        let keyCode: Int
        let resolvesTo: String
    }

    /// Stands in for the machine's Latin layout: US positions, which the shortcut letters were
    /// chosen against.
    ///
    /// Every keycode any test below mentions has an entry, `n` and `y` included. A missing entry
    /// makes the fallback return nil, which resolves to the typed character by a different route —
    /// so a row whose keycode was absent would pass under a keycode-first implementation too.
    static let usLayout: [UInt16: String] = [
        UInt16(kVK_ANSI_B): "b", UInt16(kVK_ANSI_I): "i", UInt16(kVK_ANSI_V): "v",
        UInt16(kVK_ANSI_X): "x", UInt16(kVK_ANSI_U): "u", UInt16(kVK_ANSI_Z): "z",
        UInt16(kVK_ANSI_A): "a", UInt16(kVK_ANSI_Q): "q", UInt16(kVK_ANSI_P): "p",
        UInt16(kVK_ANSI_E): "e", UInt16(kVK_ANSI_N): "n", UInt16(kVK_ANSI_Y): "y"
    ]

    private func resolve(
        _ typed: String, keyCode: Int, shift: Bool = false,
        through layout: [UInt16: String] = Self.usLayout
    ) throws -> String {
        let event = try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero,
                modifierFlags: shift ? [.command, .shift] : .command, timestamp: 0,
                windowNumber: 0, context: nil, characters: typed,
                charactersIgnoringModifiers: typed, isARepeat: false, keyCode: UInt16(keyCode)))

        return KeyboardLayout.commandKey(for: event) { layout[$0] }
    }

    // MARK: - Non-Latin layouts

    /// The defect this closes: on a Cyrillic layout the app's own shortcuts reached nothing, and
    /// ⌘V fell through to `NSTextView.paste` — the #117 path. Greek, Hebrew and Arabic are here
    /// because nothing about the fix is Cyrillic-specific.
    @Test(
        arguments: [
            // Russian ЙЦУКЕН
            Keystroke(typed: "и", keyCode: kVK_ANSI_B, resolvesTo: "b"),
            Keystroke(typed: "ш", keyCode: kVK_ANSI_I, resolvesTo: "i"),
            Keystroke(typed: "м", keyCode: kVK_ANSI_V, resolvesTo: "v"),
            Keystroke(typed: "ч", keyCode: kVK_ANSI_X, resolvesTo: "x"),
            Keystroke(typed: "г", keyCode: kVK_ANSI_U, resolvesTo: "u"),
            Keystroke(typed: "я", keyCode: kVK_ANSI_Z, resolvesTo: "z"),
            Keystroke(typed: "ф", keyCode: kVK_ANSI_A, resolvesTo: "a"),
            Keystroke(typed: "й", keyCode: kVK_ANSI_Q, resolvesTo: "q"),
            Keystroke(typed: "з", keyCode: kVK_ANSI_P, resolvesTo: "p"),
            // Greek, Hebrew, Arabic — same key, same answer.
            Keystroke(typed: "β", keyCode: kVK_ANSI_B, resolvesTo: "b"),
            Keystroke(typed: "ב", keyCode: kVK_ANSI_B, resolvesTo: "b"),
            Keystroke(typed: "لا", keyCode: kVK_ANSI_B, resolvesTo: "b")
        ])
    func aNonLatinKeystrokeResolvesToTheLatinLetterOnThatKey(_ press: Keystroke) throws {
        #expect(try resolve(press.typed, keyCode: press.keyCode) == press.resolvesTo)
    }

    /// With no ASCII-capable layout to fall back to, a non-Latin keystroke resolves to itself and
    /// so matches nothing, rather than matching some other command.
    @Test func withoutAFallbackTheKeystrokeStillMatchesNothing() throws {
        #expect(try resolve("и", keyCode: kVK_ANSI_B, through: [:]) == "и")
    }

    // MARK: - Latin layouts keep their own letters

    /// The reason this is not `event.keyCode`: keycodes are positions, not letters. On AZERTY the
    /// key labelled A is `kVK_ANSI_Q`, so dispatching on the keycode would make ⌘A quit the app.
    /// Every one of these types ASCII, so the layout's own character wins before the fallback.
    @Test(
        arguments: [
            // French AZERTY: A and Q are swapped as positions.
            Keystroke(typed: "a", keyCode: kVK_ANSI_Q, resolvesTo: "a"),
            Keystroke(typed: "q", keyCode: kVK_ANSI_A, resolvesTo: "q"),
            // Dvorak: the key at B's position types "x", and "b" lives at N's.
            Keystroke(typed: "x", keyCode: kVK_ANSI_B, resolvesTo: "x"),
            Keystroke(typed: "b", keyCode: kVK_ANSI_N, resolvesTo: "b"),
            // German QWERTZ, where Z and Y are swapped.
            Keystroke(typed: "z", keyCode: kVK_ANSI_Y, resolvesTo: "z"),
            Keystroke(typed: "y", keyCode: kVK_ANSI_Z, resolvesTo: "y")
        ])
    func aLatinLayoutKeepsTheLetterItTyped(_ press: Keystroke) throws {
        #expect(try resolve(press.typed, keyCode: press.keyCode) == press.resolvesTo)
    }

    // MARK: - Case folding

    /// Shift is reported by `hasShift`, so the resolved character is lowercase either way. "У" is
    /// Cyrillic, the one case where folding and the fallback both apply.
    @Test(
        arguments: [
            Keystroke(typed: "V", keyCode: kVK_ANSI_V, resolvesTo: "v"),
            Keystroke(typed: "Z", keyCode: kVK_ANSI_Z, resolvesTo: "z"),
            Keystroke(typed: "У", keyCode: kVK_ANSI_E, resolvesTo: "e")
        ])
    func shiftDoesNotChangeTheCharacterTheTablesSee(_ press: Keystroke) throws {
        #expect(
            try resolve(press.typed, keyCode: press.keyCode, shift: true) == press.resolvesTo)
    }

    // MARK: - Punctuation and digits

    /// ⌘+/⌘-/⌘0–⌘7 need no fallback on the layouts this was reported against: Cyrillic and Greek
    /// leave the digit row and `=`/`-` where US has them, so they already arrive as ASCII.
    @Test(
        arguments: [
            ("=", kVK_ANSI_Equal), ("-", kVK_ANSI_Minus), ("+", kVK_ANSI_Equal),
            ("1", kVK_ANSI_1), ("7", kVK_ANSI_7), ("0", kVK_ANSI_0)
        ] as [(String, Int)])
    func punctuationAndDigitsPassStraightThrough(typed: String, keyCode: Int) throws {
        // Through an empty layout: whatever this resolves to, it was not the fallback that did it.
        #expect(try resolve(typed, keyCode: keyCode, through: [:]) == typed)
    }

    // MARK: - The real translation

    /// One test of the shipping fallback rather than an injected one, so the Carbon call is known
    /// to work and not merely to compile. Skipped where the machine's ASCII-capable layout is not
    /// US-positioned, since that is a fact about the machine rather than about the code.
    @Test(.enabled(if: KeyboardLayout.asciiCharacter(forKeyCode: UInt16(kVK_ANSI_B)) == "b"))
    func theMachinesOwnLayoutTranslatesTheAlphabet() throws {
        for (keyCode, expected) in Self.usLayout {
            #expect(KeyboardLayout.asciiCharacter(forKeyCode: keyCode) == expected)
        }

        let event = try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                windowNumber: 0, context: nil, characters: "и",
                charactersIgnoringModifiers: "и", isARepeat: false,
                keyCode: UInt16(kVK_ANSI_B)))

        #expect(
            KeyboardLayout.commandKey(for: event) == "b",
            "the whole path, with no stand-in layout in it")
    }
}
