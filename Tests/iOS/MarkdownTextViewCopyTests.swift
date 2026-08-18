import Testing
import UIKit

@testable import Heptad

/// What ⌘C puts on the clipboard, which on iOS is a whole platform's worth of behaviour the macOS
/// suites cannot reach.
///
/// The buffer holds no delimiters in formatted mode, so copying its characters would take a note's
/// formatting off the clipboard — and iOS's paste is plain, so pasting it back into another note
/// gave unformatted text. `MarkdownTextViewTests.copyingAStyledNoteRoundTripsExactly` pins the
/// same guarantee on macOS; the iOS target does not compile that suite.
///
/// Asserted on `markdownForSelection` rather than on `UIPasteboard`, which is a system service
/// this process cannot depend on being reachable. What the pasteboard is handed is one assignment
/// past this.
@MainActor
struct MarkdownTextViewCopyTests {

    private func textView(_ markdown: String, plainText: Bool = false) -> MarkdownTextView {
        let view = MarkdownTextView()
        view.apply(MarkdownStyling.Appearance(plainText: plainText, fontSize: 16))
        view.load(markdown: markdown)
        return view
    }

    /// A copied run carries its `**` even though nothing on screen shows one.
    @Test func copyingAStyledSelectionTakesItsDelimitersWithIt() {
        let view = textView("pass: **rotate-me**")

        // "pass: rotate-me" — the bold run, without the space before it.
        view.selectedRange = NSRange(location: 6, length: 9)

        #expect(view.markdownForSelection == "**rotate-me**")
    }

    /// The whole note, so a copy from one note into another is exact rather than merely close.
    @Test func copyingEverythingGivesTheNoteBack() {
        let source = "- [ ] rotate ~~the~~ _keys_"
        let view = textView(source)

        view.selectedRange = NSRange(location: 0, length: (view.text ?? "").utf16.count)

        #expect(view.markdownForSelection == source)
    }

    /// In plain mode the buffer already is the source, so a copy is the characters as they are.
    @Test func copyingInPlainModeTakesTheCharactersAsTheyAre() {
        let view = textView("pass: **rotate-me**", plainText: true)

        view.selectedRange = NSRange(location: 6, length: 13)

        #expect(view.markdownForSelection == "**rotate-me**")
    }

    /// Nothing selected is nothing to write — and writing it anyway would empty the user's
    /// clipboard on a stray ⌘C.
    @Test func copyingAnEmptySelectionWritesNothing() {
        let view = textView("keys")

        view.selectedRange = NSRange(location: 2, length: 0)

        #expect(view.markdownForSelection.isEmpty)
    }
}
