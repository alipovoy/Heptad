import AppKit
import Testing

@testable import Heptad

/// What ⌘B, ⌘I, ⌘⇧X and ⌘+/⌘- do, as opposed to which keystroke reaches them —
/// `EditorShortcutManagerTests` covers the dispatch table that routes to these.
///
/// Every formatting command is a text edit now: they write markdown delimiters instead of
/// mutating attributes, so what a note holds stays something the commands can take back out
/// (#117). Font size left the text entirely and became an app-wide zoom.
///
/// `NSTextView` is a main-actor type, and the suite drives it directly.
@MainActor
final class EditorFormattingTests {
    private let scratchDefaults: ScratchDefaults
    private let notificationCenter = NotificationCenter()
    private let textView: MarkdownTextView
    private let manager: EditorShortcutManager

    init() throws {
        // A scratch suite rather than `.standard`, so a killed run can never leave the real app's
        // stored state behind it — ⌘+ and ⌘- write to whichever suite they are given.
        scratchDefaults = try ScratchDefaults(name: "EditorFormattingTests")

        textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        textView.string = "Test Text"

        manager = EditorShortcutManager(
            notificationCenter: notificationCenter, defaults: scratchDefaults.defaults)
    }

    // MARK: - Emphasis

    @Test(arguments: [
        (MarkdownFormatting.Emphasis.strong, "**Test** Text"),
        (.emphasis, "_Test_ Text"),
        (.strikethrough, "~~Test~~ Text")
    ])
    func togglingEmphasisWrapsTheSelection(
        emphasis: MarkdownFormatting.Emphasis, expected: String
    ) {
        textView.setSelectedRange(NSRange(location: 0, length: 4))  // "Test"

        manager.toggleEmphasis(emphasis, on: textView)

        #expect(textView.string == expected)
    }

    /// The property the whole markdown swap is built on: every command is its own inverse, so
    /// nothing it can add is beyond its reach afterwards.
    ///
    /// Wrapping leaves the inner text selected, which is what lets the second press find its own
    /// delimiters sitting just outside the selection.
    @Test(arguments: MarkdownFormatting.Emphasis.allCases)
    func togglingEmphasisTwiceLeavesTheTextAsItWas(emphasis: MarkdownFormatting.Emphasis) {
        textView.setSelectedRange(NSRange(location: 0, length: 4))

        manager.toggleEmphasis(emphasis, on: textView)
        manager.toggleEmphasis(emphasis, on: textView)

        #expect(textView.string == "Test Text")
        #expect(textView.selectedRange() == NSRange(location: 0, length: 4))
    }

    /// Selecting the delimiters along with the text is the other way to ask for them off.
    @Test func togglingEmphasisOverTheWholeRunUnwrapsIt() {
        textView.string = "**Test** Text"
        textView.setSelectedRange(NSRange(location: 0, length: 8))  // "**Test**"

        manager.toggleEmphasis(.strong, on: textView)

        #expect(textView.string == "Test Text")
    }

    /// With nothing selected the command inserts an empty pair and puts the caret between the
    /// halves, so ⌘B then typing comes out bold — what it did when it moved typing attributes.
    @Test func togglingEmphasisWithoutSelectionOpensAPairAroundTheCaret() {
        textView.setSelectedRange(NSRange(location: 4, length: 0))

        manager.toggleEmphasis(.strong, on: textView)

        #expect(textView.string == "Test**** Text")
        #expect(textView.selectedRange() == NSRange(location: 6, length: 0))
    }

    @Test func togglingEmphasisStylesTheWrappedText() throws {
        textView.setSelectedRange(NSRange(location: 0, length: 4))

        manager.toggleEmphasis(.strong, on: textView)
        textView.restyle()

        let storage = try #require(textView.textStorage)
        let font = try #require(storage.attribute(.font, at: 3, effectiveRange: nil) as? NSFont)
        #expect(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
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
        #expect(textView.string == "**Test** Text")

        textView.undoManager?.undo()

        #expect(textView.string == "Test Text")
    }

    /// ⌘⇧X is the same path as ⌘B and ⌘I, which is the point of it being one line.
    @Test func strikethroughTogglesBothWays() {
        textView.setSelectedRange(NSRange(location: 0, length: 4))

        manager.toggleStrikethrough(on: textView)
        #expect(textView.string == "~~Test~~ Text")

        manager.toggleStrikethrough(on: textView)
        #expect(textView.string == "Test Text")
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
    @Test func changeFontSizeLeavesTheTextAlone() {
        textView.setSelectedRange(NSRange(location: 0, length: 4))

        manager.changeFontSize(increase: true)

        #expect(textView.string == "Test Text")
    }

    /// Shrinking stops at the floor and stays there rather than marching down to an unreadable
    /// size — and, since ⌘- repeats while held, stays there for every keystroke after it.
    @Test func decreasingFontSizeStopsAtTheFloor() {
        let floor = AppConstants.Layout.minFontSize
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
        let ceiling = AppConstants.Layout.maxFontSize
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
    @Test(arguments: [Double(0), -12, 5000])
    func anOutOfRangeStoredSizeIsClampedOnRead(stored: Double) {
        scratchDefaults.defaults.set(stored, forKey: AppConstants.editorFontSizeKey)

        let size = EditorFontSize.current(scratchDefaults.defaults)

        #expect(size >= AppConstants.Layout.minFontSize)
        #expect(size <= AppConstants.Layout.maxFontSize)
    }

    /// The editors repaint on this notification, so a step that changes nothing must not post it
    /// — otherwise a held ⌘+ at the ceiling would restyle every cached note per keystroke.
    @Test func steppingAtABoundPostsNothing() {
        scratchDefaults.defaults.set(
            Double(AppConstants.Layout.maxFontSize), forKey: AppConstants.editorFontSizeKey)

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
