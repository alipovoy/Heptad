import Foundation

/// The half of `MarkdownWriting` that reads: whether a candidate line, put back through the
/// parser, gives the line it was written from.
///
/// Split out of that file rather than living beside the writing it checks, because the two
/// together no longer fit under the 400-line ceiling `swiftlint` holds this project to. It is a
/// clean cut — nothing here writes a character, and the writer reaches it through one call — but
/// the cut has a cost, and this is it: `reads` and `destination` are internal rather than
/// `private`, since `private` is file scope and they are now used across two files.
extension MarkdownWriting {
    /// Whether `markdown` reads back as the text it was written from: the same characters, and no
    /// formatting on them the text did not already have.
    ///
    /// The characters alone are not enough. `a***b**` has exactly the characters of `a*` followed
    /// by a bold `b`, and reads back as a bold `*b`; only comparing the formatting catches it.
    ///
    /// Asymmetric on purpose, and this is the half that is easy to get wrong. Formatting the
    /// writer *cannot spell* is dropped by design — the rules at the top of this file are all
    /// losses — so a check that called those failures would reject the writer's own correct
    /// output and send the line to a candidate that keeps less. What must never pass is the other
    /// direction: emphasis on characters that never carried it, which is why escaping exists.
    static func reads(_ markdown: String, as original: NSAttributedString) -> Bool {
        let rendered = RichTextRendering.attributed(from: markdown, appearance: reading)

        // Lengths as well as characters, and the lengths first: `String ==` is canonical
        // equivalence while `length` counts UTF-16 units, and the two disagree — `\u{1100}\u{1161}`
        // equals `\u{AC00}` at lengths 2 and 1. Nothing on this path renormalizes, so the loop
        // below was never actually reading past the end of `original`; this is what makes its
        // bound correct by construction rather than by that argument.
        guard rendered.length == original.length, rendered.string == original.string else {
            return false
        }

        // Walked by run, not by character: both strings answer alike over the overlap of a run
        // in each, so asking per UTF-16 unit asked the same two dictionaries over and over —
        // 63,160 lookups for a 15,790-unit note of ~1,200 runs, 32 ms of a 128 ms save.
        var index = 0
        while index < rendered.length {
            var readRun = NSRange(location: 0, length: 0)
            let read = rendered.attributes(at: index, effectiveRange: &readRun)

            var intendedRun = NSRange(location: 0, length: 0)
            _ = original.attributes(at: index, effectiveRange: &intendedRun)

            // The last unit of the overlap is asked on its own, because it is the only one whose
            // *neighbour* can carry something else — and `intent` reads that neighbour, for the
            // surrogate pair whose halves were given different attributes. Everywhere before it,
            // the neighbour is inside this same run and adds nothing.
            let step = min(NSMaxRange(readRun), NSMaxRange(intendedRun))
            if step - 1 > index, !justifies(intent(of: original, at: index), read) { return false }
            if !justifies(intent(of: original, at: step - 1), read) { return false }

            index = step
        }

        return true
    }

    /// Whether what the note meant at a position can account for what was read back at it.
    /// One-way, for the reason `reads` gives.
    private static func justifies(
        _ intended: [[NSAttributedString.Key: Any]], _ read: [NSAttributedString.Key: Any]
    ) -> Bool {
        let link = destination(read[.link])

        return Emphasis.allCases.allSatisfy { trait in
            !trait.isOn(read) || intended.contains(where: trait.isOn)
        } && (link == nil || intended.contains { link == destination($0[.link]) })
    }

    /// What the note means the character at `index` to carry — both halves of it, when it has two.
    ///
    /// A surrogate pair is one character across two indices, and an attribute may start between
    /// them. `MarkdownSlicing.aligned` moves the writer's boundaries off that split, so the lead
    /// half comes back carrying what the trail half was given; reading that as formatting
    /// appearing out of nowhere would send the line to a candidate that keeps less.
    private static func intent(
        of original: NSAttributedString, at index: Int
    ) -> [[NSAttributedString.Key: Any]] {
        var halves = [original.attributes(at: index, effectiveRange: nil)]
        let source = original.string as NSString

        if index + 1 < source.length, UTF16.isLeadSurrogate(source.character(at: index)) {
            halves.append(original.attributes(at: index + 1, effectiveRange: nil))
        }

        return halves
    }

    /// The appearance the check reads with. Only traits are compared and traits carry no size,
    /// so the note's own zoom never has to reach this file.
    private static let reading = MarkdownStyling.Appearance(
        plainText: false, fontSize: AppConstants.Layout.defaultFontSize)
}
