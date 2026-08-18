import Foundation

/// The half of `MarkdownWriting` that reads: whether a candidate line, put back through the
/// parser, gives the line it was written from.
///
/// A separate file only because the two together no longer fit under the 400-line ceiling
/// `swiftlint` holds this project to. That is also why `reads` and `destination` are internal
/// rather than `private`: `private` is file scope.
extension MarkdownWriting {
    /// Whether `markdown` reads back as the text it was written from: the same characters, and no
    /// formatting on them the text did not already have.
    ///
    /// The characters alone are not enough. `a***b**` has exactly the characters of `a*` followed
    /// by a bold `b`, and reads back as a bold `*b`; only comparing the formatting catches it.
    ///
    /// One-way on purpose: formatting the writer cannot spell is dropped by design, so calling
    /// those losses failures would reject the writer's own correct output. What must never pass is
    /// the other direction — emphasis on characters that never carried it.
    static func reads(_ markdown: String, as original: NSAttributedString) -> Bool {
        let rendered = RichTextRendering.attributed(from: markdown, appearance: reading)

        // Lengths first, then characters: `String ==` is canonical equivalence while `length`
        // counts UTF-16 units, and the two disagree — `\u{1100}\u{1161}` equals `\u{AC00}` at
        // lengths 2 and 1. This is what keeps the loop below inside `original`.
        guard rendered.length == original.length, rendered.string == original.string else {
            return false
        }

        // Walked by run, not by character: both strings answer alike over the overlap of a run in
        // each, so asking per UTF-16 unit repeated the same two lookups — 32 ms of a 128 ms save.
        var index = 0
        while index < rendered.length {
            var readRun = NSRange(location: 0, length: 0)
            let read = rendered.attributes(at: index, effectiveRange: &readRun)

            var intendedRun = NSRange(location: 0, length: 0)
            _ = original.attributes(at: index, effectiveRange: &intendedRun)

            // The last unit of the overlap is asked on its own: it is the only one whose neighbour
            // can carry something else, and `intent` reads that neighbour. Everywhere before it,
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
    /// half comes back carrying what the trail half was given.
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
