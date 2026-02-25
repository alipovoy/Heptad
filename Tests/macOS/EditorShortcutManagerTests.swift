import XCTest

@testable import SevenNotes_macOS

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
}
