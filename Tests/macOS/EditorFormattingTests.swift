import AppKit
import Testing

@testable import Heptad

/// What ⌘B, ⌘I, ⌘+/⌘- and ⌘⇧X do to text, as opposed to which keystroke reaches them —
/// `EditorShortcutManagerTests` covers the dispatch table that routes to these.
///
/// Split into its own suite because the two halves need different fixtures: the dispatch tests
/// run against a text view that records the commands it is sent, while these need one whose text
/// storage and typing attributes can be read back after the fact.
///
/// `NSTextView` is a main-actor type, and the suite drives it directly.
@MainActor
final class EditorFormattingTests {
    private let suiteName: String
    private let defaults: UserDefaults
    private let textView: NSTextView
    private let manager: EditorShortcutManager

    init() throws {
        // A scratch suite rather than `.standard`, so a killed run can never leave the real app's
        // stored state behind it. Nothing here writes to defaults; the manager just needs one.
        suiteName = "EditorFormattingTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))

        textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        textView.string = "Test Text"
        textView.textStorage?.addAttribute(
            .font, value: NSFont.systemFont(ofSize: 14), range: NSRange(location: 0, length: 9))

        manager = EditorShortcutManager(defaults: defaults)
    }

    /// `isolated` so the AppKit teardown runs on the main actor wherever the last release lands.
    isolated deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - Fixtures

    /// The font on the first character, where every formatting assertion below looks.
    private func selectionFont() throws -> NSFont {
        let storage = try #require(textView.textStorage, "Missing text storage")
        return try #require(
            storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont,
            "Missing font attribute")
    }

    private func selectionStrikethrough() throws -> Int {
        let storage = try #require(textView.textStorage, "Missing text storage")
        return (storage.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int) ?? 0
    }

    // MARK: - Font formatting

    @Test(arguments: [NSFontTraitMask.boldFontMask, .italicFontMask])
    func toggleFontTraitAppliesTheTraitToTheSelection(trait: NSFontTraitMask) throws {
        textView.setSelectedRange(NSRange(location: 0, length: 4))  // "Test"

        manager.toggleFontTrait(trait, on: textView)

        #expect(NSFontManager.shared.traits(of: try selectionFont()).contains(trait))
    }

    @Test(arguments: [(true, CGFloat(16)), (false, CGFloat(12))])
    func changeFontSizeStepsTheSelectionByTwoPoints(increase: Bool, expected: CGFloat) throws {
        textView.setSelectedRange(NSRange(location: 0, length: 4))

        manager.changeFontSize(increase: increase, on: textView)

        #expect(try selectionFont().pointSize == expected)  // the fixture starts at 14
    }

    /// Shrinking stops at the floor and stays there rather than marching down to an unreadable
    /// size — and, since ⌘- repeats while held, stays there for every keystroke after it.
    @Test func decreasingFontSizeStopsAtTheFloor() throws {
        let floor = AppConstants.Layout.minFontSize
        try setSelectionFontSize(floor + 2)

        manager.changeFontSize(increase: false, on: textView)
        #expect(try selectionFont().pointSize == floor)

        manager.changeFontSize(increase: false, on: textView)
        #expect(try selectionFont().pointSize == floor, "The floor holds on a repeated decrease")
    }

    /// The ceiling the floor above went without: holding ⌘+ used to grow the font unbounded.
    @Test(.bug(id: 50))
    func increasingFontSizeStopsAtTheCeiling() throws {
        let ceiling = AppConstants.Layout.maxFontSize
        try setSelectionFontSize(ceiling - 2)

        manager.changeFontSize(increase: true, on: textView)
        #expect(try selectionFont().pointSize == ceiling)

        manager.changeFontSize(increase: true, on: textView)
        #expect(
            try selectionFont().pointSize == ceiling, "The ceiling holds on a repeated increase")
    }

    /// Puts "Test" at `size` and selects it, for the tests that step towards a bound.
    private func setSelectionFontSize(_ size: CGFloat) throws {
        let range = NSRange(location: 0, length: 4)
        let storage = try #require(textView.textStorage, "Missing text storage")
        storage.addAttribute(.font, value: NSFont.systemFont(ofSize: size), range: range)
        textView.setSelectedRange(range)
    }

    /// With nothing selected the change lands on the typing attributes, so the next thing typed
    /// comes out at the new size.
    @Test func changingSizeWithoutSelectionUpdatesTypingAttributes() {
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.typingAttributes[.font] = NSFont.systemFont(ofSize: 14)

        manager.changeFontSize(increase: true, on: textView)

        #expect((textView.typingAttributes[.font] as? NSFont)?.pointSize == 16)
    }

    /// Typing attributes that carry no font at all fall back to the app's default size rather
    /// than leaving the shortcut inert.
    @Test func changingSizeWithNoTypingFontStartsFromTheDefaultSize() throws {
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.typingAttributes = [:]
        try #require(
            textView.typingAttributes[.font] == nil,
            "The fallback is only under test while the typing attributes carry no font")

        manager.changeFontSize(increase: true, on: textView)

        #expect(
            (textView.typingAttributes[.font] as? NSFont)?.pointSize
                == AppConstants.Layout.defaultFontSize + 2)
    }

    /// The undo hook `applyFontChange` registers, driven through a real undo manager — which an
    /// `NSTextView` only has once it is in a window.
    @Test func formattingIsUndoable() throws {
        // `isReleasedWhenClosed` off before anything else: AppKit's default of releasing the
        // window on close over-releases it under ARC and takes the test process down with it.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: .borderless,
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }

        window.contentView?.addSubview(textView)
        textView.allowsUndo = true
        textView.setSelectedRange(NSRange(location: 0, length: 4))  // "Test"

        manager.toggleFontTrait(.boldFontMask, on: textView)
        #expect(NSFontManager.shared.traits(of: try selectionFont()).contains(.boldFontMask))

        textView.undoManager?.undo()

        #expect(
            NSFontManager.shared.traits(of: try selectionFont()).contains(.boldFontMask) == false)
    }

    // MARK: - Strikethrough

    @Test func strikethroughTogglesTheSelectionBothWays() throws {
        textView.setSelectedRange(NSRange(location: 0, length: 4))  // "Test"

        manager.toggleStrikethrough(on: textView)
        #expect(try selectionStrikethrough() == NSUnderlineStyle.single.rawValue)

        manager.toggleStrikethrough(on: textView)
        #expect(try selectionStrikethrough() == 0)
    }

    /// A half-struck selection has each run flipped on its own terms, the way ⌘B and ⌘I have
    /// always treated mixed selections.
    ///
    /// Reading the attribute at the start of the selection and painting that one answer over the
    /// whole range — what this used to do — makes the result depend on which end the selection
    /// happens to start at, and quietly discards the state of every run after the first.
    @Test(.bug(id: 50))
    func strikethroughFlipsEachRunOfAMixedSelection() throws {
        let storage = try #require(textView.textStorage, "Missing text storage")
        storage.addAttribute(
            .strikethroughStyle, value: NSUnderlineStyle.single.rawValue,
            range: NSRange(location: 0, length: 4))  // "Test"
        textView.setSelectedRange(NSRange(location: 0, length: 9))  // "Test Text"

        manager.toggleStrikethrough(on: textView)

        #expect(try selectionStrikethrough() == 0, "The struck run comes back unstruck")
        #expect(
            (storage.attribute(.strikethroughStyle, at: 5, effectiveRange: nil) as? Int)
                == NSUnderlineStyle.single.rawValue,
            "The unstruck run is struck, rather than following whatever the first character had")
    }

    @Test func strikethroughWithoutSelectionUpdatesTypingAttributes() {
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        manager.toggleStrikethrough(on: textView)
        #expect(
            (textView.typingAttributes[.strikethroughStyle] as? Int)
                == NSUnderlineStyle.single.rawValue)

        manager.toggleStrikethrough(on: textView)
        #expect((textView.typingAttributes[.strikethroughStyle] as? Int) == 0)
    }
}
