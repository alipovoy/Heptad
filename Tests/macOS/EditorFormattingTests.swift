import AppKit
import Testing

@testable import Heptad

/// What ⌘B, ⌘I, ⌘⇧X and ⌘+/⌘- do, as opposed to which keystroke reaches them —
/// `EditorShortcutManagerTests` covers the dispatch table that routes to these.
///
/// Every formatting command is an attribute change: formatted mode holds rich text, so ⌘B turns
/// bold on over the selection rather than typing delimiters around it (#124). What the note
/// *stores* is still markdown, which is what `markdown` reads back here. Font size is neither —
/// it left the text entirely and became an app-wide zoom.
///
/// `NSTextView` is a main-actor type, and the suite drives it directly.
@MainActor
struct EditorFormattingTests {
    private let scratchDefaults: ScratchDefaults
    private let notificationCenter = NotificationCenter()
    private let textView: MarkdownTextView
    private let manager: EditorShortcutManager

    /// What the buffer carries, which is what the user is looking at — see `carrying(_:)`. Every
    /// command assertion below reads this beside the markdown, because the writer can correct on
    /// the way to the store exactly what a broken command got wrong.
    private func carrying(_ emphasis: Emphasis) throws -> String {
        try #require(textView.textStorage).carrying(emphasis)
    }

    init() throws {
        // A scratch suite rather than `.standard`, so a killed run can never leave the real app's
        // stored state behind it — ⌘+ and ⌘- write to whichever suite they are given.
        scratchDefaults = try ScratchDefaults(name: "EditorFormattingTests")

        textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        textView.load(markdown: "Test Text")

        manager = EditorShortcutManager(
            notificationCenter: notificationCenter, defaults: scratchDefaults.defaults)
    }

    // MARK: - Emphasis

    @Test(arguments: [
        (Emphasis.strong, "**Test** Text"),
        (.emphasis, "_Test_ Text"),
        (.strikethrough, "~~Test~~ Text")
    ])
    func togglingEmphasisAppliesItToTheSelection(emphasis: Emphasis, stored: String) throws {
        textView.setSelectedRange(NSRange(location: 0, length: 4))  // "Test"

        manager.toggleEmphasis(emphasis, on: textView)

        #expect(textView.string == "Test Text", "The buffer holds no delimiters")
        #expect(try carrying(emphasis) == "####.....", "the trait is on `Test` and nothing else")
        #expect(textView.markdown == stored, "and the note stores them")
    }

    /// Every command is its own inverse. Under delimiters this held only when the second press
    /// found its own pair still sitting beside the selection; a trait needs no such luck.
    @Test(arguments: Emphasis.allCases)
    func togglingEmphasisTwiceLeavesTheNoteAsItWas(emphasis: Emphasis) throws {
        textView.setSelectedRange(NSRange(location: 0, length: 4))

        manager.toggleEmphasis(emphasis, on: textView)
        manager.toggleEmphasis(emphasis, on: textView)

        #expect(try carrying(emphasis) == ".........", "and takes it off the buffer, not just the store")
        #expect(textView.markdown == "Test Text")
        #expect(textView.selectedRange() == NSRange(location: 0, length: 4))
    }

    /// The reported bug in #124, in the order that produced it: bold, then italic, then bold off
    /// again. Under delimiters the second ⌘B could not see the `**` — the italic pair had moved
    /// it out of reach — so it wrapped a second time and left `**_**hello**_**` on screen.
    @Test(.bug(id: 124)) func emphasisCommandsComposeInAnyOrder() throws {
        textView.setSelectedRange(NSRange(location: 0, length: 4))

        manager.toggleEmphasis(.strong, on: textView)
        manager.toggleEmphasis(.emphasis, on: textView)
        manager.toggleEmphasis(.strong, on: textView)

        #expect(try carrying(.emphasis) == "####.....", "Taking the bold off leaves the italic on")
        #expect(try carrying(.strong) == ".........")
        #expect(textView.markdown == "_Test_ Text")
        #expect(textView.string == "Test Text")
    }

    /// Deleting the last character of a formatted run is an ordinary deletion now. Under
    /// delimiters it emptied the pair into `****`, four literal asterisks the user never typed.
    @Test(.bug(id: 124)) func emptyingAFormattedRunLeavesNothingBehind() throws {
        textView.load(markdown: "**a** b")
        textView.setSelectedRange(NSRange(location: 1, length: 0))

        textView.deleteBackward(nil)

        #expect(textView.string == " b")
        #expect(textView.markdown == " b", "and nothing is left in the note to look at")
    }

    /// One press, on the buffer a note switch produces rather than a freshly typed line.
    ///
    /// The direction is decided by asking whether the selection already carries the trait, and a
    /// reloaded note has bare newlines between its runs — so the terminator answered "no", the
    /// press re-applied bold that was already there, and nothing appeared to happen until the
    /// second press. Single-line selections never showed it.
    @Test(arguments: [("**a**\n**b**", "a\nb"), ("**a**\n\n**b**", "a\n\nb")])
    func takingEmphasisOffAReloadedMultiLineRunTakesOnePress(
        source: String, stripped: String
    ) throws {
        textView.load(markdown: source)
        textView.setSelectedRange(NSRange(location: 0, length: (textView.string as NSString).length))

        manager.toggleEmphasis(.strong, on: textView)

        // On the buffer, because this is the press that used to be a no-op: the store was right
        // one press late, so a store-only assertion saw the correct answer and not the bug.
        #expect(
            try carrying(.strong).allSatisfy { $0 == "." },
            "one press, and nothing is left bold")
        #expect(textView.markdown == stripped)
    }

    /// With nothing selected the command arms the caret, so ⌘B then typing comes out bold —
    /// without putting a single character in the note for a press the user then thinks better of.
    @Test func togglingEmphasisWithoutSelectionArmsTheCaret() throws {
        textView.setSelectedRange(NSRange(location: 9, length: 0))

        manager.toggleEmphasis(.strong, on: textView)

        #expect(textView.string == "Test Text", "Nothing typed yet, nothing written")
        #expect(try carrying(.strong) == ".........", "and nothing already there turned bold")

        textView.insertText(" more", replacementRange: NSRange(location: 9, length: 0))
        // All five typed characters are bold, the leading space included — the writer is what
        // puts that space outside the pair on the way to the store. The two lines disagreeing is
        // the normal case, not a bug: one is what the user sees, the other is what is stored.
        #expect(try carrying(.strong) == ".........#####")
        #expect(textView.markdown == "Test Text **more**")
    }

    @Test func togglingEmphasisStylesTheSelectedText() throws {
        textView.setSelectedRange(NSRange(location: 0, length: 4))

        manager.toggleEmphasis(.strong, on: textView)

        let storage = try #require(textView.textStorage)
        let font = try #require(storage.attribute(.font, at: 3, effectiveRange: nil) as? NSFont)
        #expect(font.isBold)
    }

    /// Driven through a real undo manager, which an `NSTextView` only has once it is in a window.
    @Test(.tags(.windowServer))
    func formattingIsUndoable() {
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

        manager.toggleEmphasis(.strong, on: textView)
        #expect(textView.markdown == "**Test** Text")

        textView.undoManager?.undo()

        #expect(textView.markdown == "Test Text")
    }

    // MARK: - Font size

    @Test(arguments: [(true, CGFloat(18)), (false, CGFloat(14))])
    func changeFontSizeStepsTheZoomByTwoPoints(increase: Bool, expected: CGFloat) {
        manager.changeFontSize(increase: increase)

        // The fixture starts at the app default, which is what an unset suite reports.
        #expect(EditorFontSize.current(scratchDefaults.defaults) == expected)
    }

    /// The size is a view setting now, so the command must not touch the note's text — the one
    /// piece of formatting that could not survive the swap had to leave the buffer entirely.
    /// Shrinking stops at the floor and stays there rather than marching down to an unreadable
    /// size — and, since ⌘- repeats while held, stays there for every keystroke after it.
    @Test func decreasingFontSizeStopsAtTheFloor() {
        let floor = EditorFontSize.minimumSize
        scratchDefaults.defaults.set(Double(floor + 2), forKey: AppConstants.editorFontSizeKey)

        manager.changeFontSize(increase: false)
        #expect(EditorFontSize.current(scratchDefaults.defaults) == floor)

        manager.changeFontSize(increase: false)
        #expect(
            EditorFontSize.current(scratchDefaults.defaults) == floor,
            "The floor holds on a repeated decrease")
    }

    /// The ceiling the floor above went without: holding ⌘+ used to grow the font unbounded.
    @Test(.bug(id: 50))
    func increasingFontSizeStopsAtTheCeiling() {
        let ceiling = EditorFontSize.maximumSize
        scratchDefaults.defaults.set(Double(ceiling - 2), forKey: AppConstants.editorFontSizeKey)

        manager.changeFontSize(increase: true)
        #expect(EditorFontSize.current(scratchDefaults.defaults) == ceiling)

        manager.changeFontSize(increase: true)
        #expect(
            EditorFontSize.current(scratchDefaults.defaults) == ceiling,
            "The ceiling holds on a repeated increase")
    }

    /// A junk value written from outside the app is clamped on read rather than reaching text
    /// layout. The stored size is plain `UserDefaults` and nothing sanity-checks it on write.
    ///
    /// The non-finite three are here because the clamp is two comparisons, and every comparison
    /// against NaN is false — so it passed straight through both bounds.
    @Test(arguments: [Double(0), -12, 5000, .nan, .infinity, -.infinity])
    func anOutOfRangeStoredSizeIsClampedOnRead(stored: Double) {
        scratchDefaults.defaults.set(stored, forKey: AppConstants.editorFontSizeKey)

        let size = EditorFontSize.current(scratchDefaults.defaults)

        #expect(size >= EditorFontSize.minimumSize)
        #expect(size <= EditorFontSize.maximumSize)
    }

    /// And a stored NaN can be stepped off, which is what made it worse than the rest of the junk.
    ///
    /// `step` bails on `stepped != size`, and `nan != nan` is true, so both keys rewrote the NaN
    /// and posted a repaint at a size AppKit substitutes 13 pt for. The only way out was
    /// `defaults delete`.
    @Test func aStoredNaNIsSteppedOffRatherThanRewritten() {
        scratchDefaults.defaults.set(Double.nan, forKey: AppConstants.editorFontSizeKey)

        manager.changeFontSize(increase: true)

        #expect(
            EditorFontSize.current(scratchDefaults.defaults)
                == AppConstants.Layout.defaultFontSize + 2)
    }

    /// The editors repaint on this notification, so a step that changes nothing must not post it
    /// — otherwise a held ⌘+ at the ceiling would restyle every cached note per keystroke.
    @Test func steppingAtABoundPostsNothing() {
        scratchDefaults.defaults.set(
            Double(EditorFontSize.maximumSize), forKey: AppConstants.editorFontSizeKey)

        var posts = 0
        let token = notificationCenter.addObserver(
            forName: .editorFontSizeDidChange, object: nil, queue: nil) { _ in posts += 1 }
        defer { notificationCenter.removeObserver(token) }

        manager.changeFontSize(increase: true)
        #expect(posts == 0)

        manager.changeFontSize(increase: false)
        #expect(posts == 1, "A step that moves the size does post")
    }
}
