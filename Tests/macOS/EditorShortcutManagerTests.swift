import XCTest

@testable import Heptad

final class EditorShortcutManagerTests: XCTestCase {
    var textView: NSTextView!
    var manager: EditorShortcutManager!

    override func setUp() {
        super.setUp()
        textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        textView.string = "Test Text"
        let font = NSFont.systemFont(ofSize: 14)
        textView.textStorage?.addAttribute(
            .font, value: font, range: NSRange(location: 0, length: 9))

        manager = EditorShortcutManager()
    }

    override func tearDown() {
        textView = nil
        manager = nil
        super.tearDown()
    }

    func testBoldShortcutTogglesBoldFormatter() {
        textView.setSelectedRange(NSRange(location: 0, length: 4))  // "Test"

        manager.toggleFontTrait(.boldFontMask, on: textView)

        guard
            let font = textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        else {
            XCTFail("Missing font attribute")
            return
        }

        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
    }

    func testItalicShortcutTogglesItalicFormatter() {
        textView.setSelectedRange(NSRange(location: 0, length: 4))  // "Test"

        manager.toggleFontTrait(.italicFontMask, on: textView)

        guard
            let font = textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        else {
            XCTFail("Missing font attribute")
            return
        }

        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.italicFontMask))
    }

    func testIncreaseFontSizeShortcut() {
        textView.setSelectedRange(NSRange(location: 0, length: 4))

        let initialFont =
            textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let initialSize = initialFont?.pointSize ?? 14

        manager.changeFontSize(increase: true, on: textView)

        let newFont = textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let newSize = newFont?.pointSize ?? 14

        XCTAssertEqual(newSize, initialSize + 2)
    }

    func testStrikethroughShortcutTogglesStrikethroughStyle() {
        textView.setSelectedRange(NSRange(location: 0, length: 4))  // "Test"

        manager.toggleStrikethrough(on: textView)

        let value =
            textView.textStorage?.attribute(.strikethroughStyle, at: 0, effectiveRange: nil)
            as? Int
        XCTAssertEqual(value, NSUnderlineStyle.single.rawValue)

        manager.toggleStrikethrough(on: textView)

        let toggledOff =
            (textView.textStorage?.attribute(.strikethroughStyle, at: 0, effectiveRange: nil)
                as? Int) ?? 0
        XCTAssertEqual(toggledOff, 0)
    }

    func testStrikethroughWithoutSelectionUpdatesTypingAttributes() {
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        manager.toggleStrikethrough(on: textView)
        let on = (textView.typingAttributes[.strikethroughStyle] as? Int) ?? 0
        XCTAssertEqual(on, NSUnderlineStyle.single.rawValue)

        manager.toggleStrikethrough(on: textView)
        let off = (textView.typingAttributes[.strikethroughStyle] as? Int) ?? 0
        XCTAssertEqual(off, 0)
    }

    func testSelectNoteWritesSelectedIndexForValidNote() {
        let key = AppConstants.selectedNoteIndexKey
        let original = UserDefaults.standard.object(forKey: key)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        // ⌘3 selects the third note (zero-based index 2).
        XCTAssertTrue(manager.selectNote(noteIndex: 3))
        XCTAssertEqual(UserDefaults.standard.integer(forKey: key), 2)
    }

    func testSelectNoteIgnoresOutOfRangeDigits() {
        // Digits past the note count aren't handled, so the key event passes through.
        XCTAssertFalse(manager.selectNote(noteIndex: 9))
    }

    func testUndoFormatting() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: .borderless,
            backing: .buffered, defer: false)
        window.contentView?.addSubview(textView)
        textView.allowsUndo = true

        textView.setSelectedRange(NSRange(location: 0, length: 4))  // "Test"

        manager.toggleFontTrait(.boldFontMask, on: textView)

        guard
            let boldFont = textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil)
                as? NSFont
        else {
            XCTFail("Missing font attribute")
            return
        }
        XCTAssertTrue(NSFontManager.shared.traits(of: boldFont).contains(.boldFontMask))

        // Trigger Undo
        textView.undoManager?.undo()

        guard
            let restoredFont = textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil)
                as? NSFont
        else {
            XCTFail("Missing font attribute after undo")
            return
        }
        XCTAssertFalse(NSFontManager.shared.traits(of: restoredFont).contains(.boldFontMask))
    }
}
