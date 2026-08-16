import Foundation
import Testing

#if canImport(UIKit)
    import UIKit
#else
    import AppKit
#endif

@testable import Heptad

/// The applier that turns an `Edit` into a change in the text view. There is one per platform
/// and they take different routes to the same result, so the assertions live here, where both
/// test targets run them. `ListEditingTests` covers the macOS one's undo behaviour.
@MainActor
struct TextEditApplyTests {

    private let body = PlatformFont.editorBody(
        plainText: false, size: AppConstants.Layout.defaultFontSize)

    @Test func applyingAnEditReplacesTheRange() {
        let textView = makeTextView(text: "- item")

        textView.apply(
            TextEdit(range: NSRange(location: 6, length: 0), replacement: "\n- "),
            attributes: [.font: body])

        #expect(currentText(of: textView) == "- item\n- ")
    }

    @Test func applyingAnEmptyReplacementDeletesTheRange() {
        let textView = makeTextView(text: "- item\n- ")

        textView.apply(
            TextEdit(range: NSRange(location: 7, length: 2), replacement: ""),
            attributes: [.font: body])

        #expect(currentText(of: textView) == "- item\n")
    }

    /// The replacement carries the attributes it was given, not the ones it lands beside.
    ///
    /// Asserted on both platforms because they take different routes to it: UIKit inserts through
    /// the input system with `typingAttributes`, AppKit replaces with an attributed string.
    @Test func theReplacementCarriesTheAttributesItWasGiven() throws {
        let textView = makeTextView(text: "- item", font: body.bolded())

        textView.apply(
            TextEdit(range: NSRange(location: 6, length: 0), replacement: "\n- "),
            attributes: [.font: body])

        #expect(currentText(of: textView) == "- item\n- ")
        #expect(try font(of: textView, at: 0).isBold, "the run it was inserted beside is untouched")
        #expect(try font(of: textView, at: 8).isBold == false, "and the replacement is not bold")
    }

    #if canImport(UIKit)
        private func makeTextView(text: String, font: PlatformFont? = nil) -> UITextView {
            let textView = UITextView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
            textView.attributedText = NSAttributedString(
                string: text, attributes: [.font: font ?? body])
            return textView
        }

        private func currentText(of textView: UITextView) -> String { textView.text }

        private func font(of textView: UITextView, at location: Int) throws -> PlatformFont {
            try #require(
                textView.textStorage.attribute(.font, at: location, effectiveRange: nil)
                    as? PlatformFont)
        }
    #else
        private func makeTextView(text: String, font: PlatformFont? = nil) -> NSTextView {
            let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
            textView.textStorage?.setAttributedString(
                NSAttributedString(string: text, attributes: [.font: font ?? body]))
            return textView
        }

        private func currentText(of textView: NSTextView) -> String { textView.string }

        private func font(of textView: NSTextView, at location: Int) throws -> PlatformFont {
            let storage = try #require(textView.textStorage)
            return try #require(
                storage.attribute(.font, at: location, effectiveRange: nil) as? PlatformFont)
        }
    #endif
}
