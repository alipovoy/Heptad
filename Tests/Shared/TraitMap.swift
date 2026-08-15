import Foundation

@testable import Heptad

extension NSAttributedString {
    /// Which characters carry `emphasis` — `#` carries it, `.` does not, one symbol per UTF-16
    /// unit. `"######....."` is a bold `rotate` in front of a plain ` keys`.
    ///
    /// The reason the command suites read this *and* the markdown, rather than the markdown alone:
    /// a command writes the buffer, and `MarkdownWriting` re-derives the same whitespace and
    /// word-boundary rules on the way to the store. A command that formats the wrong characters can
    /// therefore leave a wrong buffer and a right store — the writer performs the same correction on
    /// the way past — and an assertion taken from the store cannot see it. Measured: dropping the
    /// trim from `AttributedFormatting.toggle` puts the trailing space in bold on screen and leaves
    /// all 287 tests green.
    ///
    /// So: an assertion about a command belongs on the buffer the command wrote. The store
    /// assertions stay beside them — those are the round-trip guarantee, and they belong too.
    func carrying(_ emphasis: Emphasis) -> String {
        (0..<length).reduce(into: "") { map, location in
            map += emphasis.isOn(attributes(at: location, effectiveRange: nil)) ? "#" : "."
        }
    }
}
