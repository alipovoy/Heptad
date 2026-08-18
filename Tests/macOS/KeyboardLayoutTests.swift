import AppKit
import Carbon.HIToolbox
import Testing

@testable import Heptad

/// Which character a ⌘ keystroke is dispatched on, layout by layout.
///
/// `NSEvent.keyEvent` takes `charactersIgnoringModifiers` and `keyCode` as separate arguments, so
/// every layout below can be synthesized here — no input source has to be installed to test the
/// one thing that only shows up on a non-Latin one.
///
/// The fallback is injected in most of these. The shipping translation reads whichever layouts the
/// machine has, and a test that asserted "и" resolves to "b" through the real one would be
/// asserting a fact about the machine; `theMachinesOwnLayoutTranslatesTheAlphabet` does exactly
/// that, once, and skips where it does not hold.
@Suite struct KeyboardLayoutTests {

    /// One keystroke and the character the shortcut tables must see for it.
    struct Keystroke: Sendable {
        let typed: String
        let keyCode: Int
        let resolvesTo: String
    }

    /// Stands in for the machine's Latin layout: US positions, which is what the shortcut letters
    /// were chosen against.
    ///
    /// Every keycode any test below mentions has an entry, including the ones no shortcut uses
    /// (`n`, `y`). A missing entry makes the fallback return nil, which resolves to the typed
    /// character by a *different* route — so a row whose keycode was absent would pass under a
    /// keycode-first implementation too, and prove nothing.
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

    /// The finding this closes: on a Cyrillic layout the app's own shortcuts reached nothing, and
    /// ⌘V fell through to `NSTextView.paste` — the #117 path, which is what pasting formatting into
    /// the storage was called the first time.
    ///
    /// Russian is the layout it was reported on; the other three are here because nothing about the
    /// fix is Cyrillic-specific and a Greek or Hebrew user would have filed the same bug.
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
    /// so matches nothing — which is what it did before this existed. It must not resolve to some
    /// *other* command instead.
    @Test func withoutAFallbackTheKeystrokeStillMatchesNothing() throws {
        #expect(try resolve("и", keyCode: kVK_ANSI_B, through: [:]) == "и")
    }

    // MARK: - Latin layouts keep their own letters

    /// The reason this is not `event.keyCode`.
    ///
    /// Keycodes are positions, not letters. On AZERTY the key labelled A is `kVK_ANSI_Q` and the
    /// one labelled Q is `kVK_ANSI_A`, so dispatching on the keycode would make ⌘A — select all,
    /// pressed over a note — quit the app instead. Dvorak scrambles it further. Every one of these
    /// types ASCII, so the layout's own character has to win before the fallback is consulted.
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

    /// Shift is reported by `hasShift`, so the resolved character is lowercase either way. This is
    /// what let the tables drop the duplicate `"Z"`, `"V"`, `"X"` and `"U"` cases that sat beside
    /// their `where hasShift` forms.
    /// "У" is Cyrillic, so it takes the fallback path with shift held — the one case where both
    /// transformations apply at once.
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
    /// to work and not merely to compile.
    ///
    /// Skipped rather than failed where the machine's ASCII-capable layout is not a US-positioned
    /// one — a Dvorak-only machine is a legitimate machine, and this asserting otherwise would be
    /// asserting a fact about the hardware.
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
