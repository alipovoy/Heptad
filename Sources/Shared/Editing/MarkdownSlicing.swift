import Foundation

/// Where a writer may cut attributed text, and where it may not.
///
/// `MarkdownWriting` spells one slice at a time — a line, a run of one trait, the non-whitespace
/// core a delimiter pair goes around — and every one of those slices is a range decided here. The
/// geometry is separate from the spelling because the two answer different questions: this file
/// only says which characters a piece is made of, and never what is written around them.
///
/// The rule underneath all of it is that slices are **adjacent and disjoint**. Every character of
/// the note belongs to exactly one of them, so the writer emits each one exactly once — which is
/// what makes "a save may lose formatting; it may never lose a character" checkable at all.
enum MarkdownSlicing {
    /// `range` split into stretches that do and do not carry `trait`, in order.
    static func sections(
        of range: NSRange, in text: NSAttributedString, carrying trait: Emphasis
    ) -> [(range: NSRange, isOn: Bool)] {
        var sections: [(range: NSRange, isOn: Bool)] = []

        text.enumerateAttributes(in: range, options: []) { attributes, subrange, _ in
            let isOn = trait.isOn(attributes)

            // Runs differing in something this trait does not care about are one stretch.
            if var last = sections.last, last.isOn == isOn {
                last.range = NSUnionRange(last.range, subrange)
                sections[sections.count - 1] = last
            } else {
                sections.append((subrange, isOn))
            }
        }

        return sections
    }

    /// `range` split at its line breaks, each newline kept with the line it ends.
    static func lines(of range: NSRange, in text: NSAttributedString) -> [NSRange] {
        let source = text.string as NSString
        var lines: [NSRange] = []
        var cursor = range.location

        while cursor < NSMaxRange(range) {
            let line = source.lineRange(for: NSRange(location: cursor, length: 0))
            let clipped = NSIntersectionRange(line, range)
            guard clipped.length > 0 else { break }

            lines.append(clipped)
            cursor = NSMaxRange(line)
        }

        return lines
    }

    /// `range` without the whitespace at its ends — the core a delimiter pair can close against.
    ///
    /// Two callers, one rule, deliberately: the writer puts a pair around this core, and `⌘B` over
    /// a selection with a trailing space formats the same core rather than the space. They were the
    /// same eight lines in two files, which meant a trait the commands would apply and the writer
    /// would then drop was one edit away — and a trait that vanishes on save is worse than one that
    /// never went on.
    static func trimmed(_ range: NSRange, in source: NSString) -> NSRange {
        var start = range.location
        var end = NSMaxRange(range)

        while start < end, MarkdownSyntax.isWhitespace(source.character(at: start)) { start += 1 }
        while end > start, MarkdownSyntax.isWhitespace(source.character(at: end - 1)) { end -= 1 }

        return NSRange(location: start, length: end - start)
    }

    /// `range` without the line terminator it ends with, if it ends with one.
    static func withoutTerminator(_ range: NSRange, in source: NSString) -> NSRange {
        var end = NSMaxRange(range)

        while end > range.location, MarkdownSyntax.isNewline(source.character(at: end - 1)) {
            end -= 1
        }

        return NSRange(location: range.location, length: end - range.location)
    }

    /// `range` with both ends moved off the tail half of a surrogate pair.
    ///
    /// A run boundary can land inside a character: `addAttribute` takes any offset, and a paste
    /// arrives with whatever offsets it was built from. `substring(with:)` then bridges the half
    /// it gets to U+FFFD, so `a🔑b` came out of a save as two replacement characters — the note's
    /// own character gone, with no later edit able to bring it back.
    ///
    /// Both ends move the same way, because adjacent slices share a boundary: moving it
    /// identically for the slice that ends there and the one that starts there keeps the two
    /// adjacent, so the character is written exactly once, whole, by whichever slice ends up
    /// holding it.
    static func aligned(_ range: NSRange, in source: NSString) -> NSRange {
        let start = boundary(at: range.location, in: source)
        let end = boundary(at: NSMaxRange(range), in: source)

        return NSRange(location: start, length: max(0, end - start))
    }

    private static func boundary(at index: Int, in source: NSString) -> Int {
        guard index > 0, index < source.length,
            UTF16.isTrailSurrogate(source.character(at: index)),
            UTF16.isLeadSurrogate(source.character(at: index - 1))
        else { return index }

        return index - 1
    }

    /// How much of `range` is the leading list marker of the line it starts on, in UTF-16 units.
    ///
    /// Asked of the line rather than of `range`, because `range` is whatever slice of it the run
    /// boundaries produced — the marker is only ever at the head of the line, and only the part
    /// of it this slice holds is the marker's.
    static func markerPrefix(of range: NSRange, in source: NSString) -> Int {
        let line = source.lineRange(for: NSRange(location: range.location, length: 0))
        guard let length = ListContinuation.markerLength(on: source.substring(with: line)) else {
            return 0
        }

        return max(0, min(line.location + length, NSMaxRange(range)) - range.location)
    }
}
