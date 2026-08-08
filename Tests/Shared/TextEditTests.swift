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

    @Test func applyingAnEditReplacesTheRange() {
        let textView = makeTextView(text: "- item")

        textView.apply(
            TextEdit(range: NSRange(location: 6, length: 0), replacement: "\n- "))

        #expect(currentText(of: textView) == "- item\n- ")
    }

    @Test func applyingAnEmptyReplacementDeletesTheRange() {
        let textView = makeTextView(text: "- item\n- ")

        textView.apply(
            TextEdit(range: NSRange(location: 7, length: 2), replacement: ""))

        #expect(currentText(of: textView) == "- item\n")
    }

    #if canImport(UIKit)
        private func makeTextView(text: String) -> UITextView {
            let textView = UITextView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
            textView.text = text
            return textView
        }

        private func currentText(of textView: UITextView) -> String { textView.text }
    #else
        private func makeTextView(text: String) -> NSTextView {
            let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
            textView.string = text
            return textView
        }

        private func currentText(of textView: NSTextView) -> String { textView.string }
    #endif
}
