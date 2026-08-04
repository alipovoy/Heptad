import Foundation

/// Turns a note's edit time into the "relative, named" string the statistics bar shows —
/// "now", "5 minutes ago", "yesterday", "last week".
///
/// `RelativeDateTimeFormatter` rather than `Date.RelativeFormatStyle`: the modern style
/// always measures against the real current instant, and the variant that takes an explicit
/// anchor (`Date.AnchoredRelativeFormatStyle`) needs macOS 15 / iOS 18, above this project's
/// deployment targets. Taking `now` as a parameter is what lets the ticker drive the label
/// and the tests assert exact strings. Output is identical for both:
/// `.named` + `.full` are what `.relative(presentation: .named)` formats with.
@MainActor
struct RelativeEditTimeFormatter {
    /// The instance the UI uses, in the user's own locale.
    static let shared = Self()

    private let formatter: RelativeDateTimeFormatter

    /// - Parameter locale: overridden only by tests, which assert on English strings.
    init(locale: Locale = .autoupdatingCurrent) {
        formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        // .named prefers "yesterday" and "now" over "1 day ago" and "0 seconds ago".
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
    }

    func string(for date: Date, relativeTo now: Date) -> String {
        formatter.localizedString(for: date, relativeTo: now)
    }
}
