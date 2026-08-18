import Foundation

@testable import Heptad

extension NSAttributedString {
    /// Which characters carry `emphasis` — `#` carries it, `.` does not, one symbol per UTF-16
    /// unit. `"######....."` is a bold `rotate` in front of a plain ` keys`.
    ///
    /// Why the command suites read this as well as the markdown: `MarkdownWriting` re-derives the
    /// same whitespace and word-boundary rules on the way to the store, so a command that formats
    /// the wrong characters can leave a wrong buffer and a right store. Dropping the trim from
    /// `AttributedFormatting.toggle` bolds the trailing space on screen with every test green.
    func carrying(_ emphasis: Emphasis) -> String {
        (0..<length).reduce(into: "") { map, location in
            map += emphasis.isOn(attributes(at: location, effectiveRange: nil)) ? "#" : "."
        }
    }
}
