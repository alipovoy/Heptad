import Testing
import UIKit

@testable import Heptad

/// What ⌘C puts on the clipboard. The buffer holds no delimiters in formatted mode, so copying
/// its characters loses the note's formatting. `MarkdownTextViewPasteTests` is the way back in.
/// `MarkdownTextViewTests.copyingAStyledNoteRoundTripsExactly` pins the same guarantee on macOS;
/// the iOS target does not compile that suite.
///
/// Asserted on `markdownForSelection` rather than on `UIPasteboard`, a system service this process
/// cannot depend on being reachable.
@MainActor
struct MarkdownTextViewCopyTests {

    /// A copied run carries its `**` even though nothing on screen shows one.
    @Test func copyingAStyledSelectionTakesItsDelimitersWithIt() {
        let view = makeTextView("pass: **rotate-me**")

        // "pass: rotate-me" — the bold run, without the space before it.
        view.selectedRange = NSRange(location: 6, length: 9)

        #expect(view.markdownForSelection == "**rotate-me**")
    }

    /// The whole note, so a copy from one note into another is exact.
    @Test func copyingEverythingGivesTheNoteBack() {
        let source = "- [ ] rotate ~~the~~ _keys_"
        let view = makeTextView(source)

        view.selectedRange = NSRange(location: 0, length: (view.text ?? "").utf16.count)

        #expect(view.markdownForSelection == source)
    }

    /// In plain mode the buffer already is the source, so a copy is the characters as they are.
    @Test func copyingInPlainModeTakesTheCharactersAsTheyAre() {
        let view = makeTextView("pass: **rotate-me**", plainText: true)

        view.selectedRange = NSRange(location: 6, length: 13)

        #expect(view.markdownForSelection == "**rotate-me**")
    }

    /// Nothing selected is nothing to write: a stray ⌘C must not empty the clipboard.
    @Test func copyingAnEmptySelectionWritesNothing() {
        let view = makeTextView("keys")

        view.selectedRange = NSRange(location: 2, length: 0)

        #expect(view.markdownForSelection.isEmpty)
    }
}
