import Foundation
import Testing

@testable import Heptad

/// Pins the wording of the edit-time label — the whole point of the "relative, named"
/// choice is what it says at each distance, so the strings are the behaviour.
///
/// Fixed to `en_US`: the shared instance follows the user's locale, and asserting English
/// against `.autoupdatingCurrent` would fail on any machine that is not set to English.
@MainActor
struct RelativeEditTimeFormatterTests {
    private let formatter = RelativeEditTimeFormatter(locale: Locale(identifier: "en_US"))

    /// An arbitrary fixed instant. Everything here is measured from it, so nothing depends
    /// on when the suite runs.
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func string(secondsAgo: TimeInterval) -> String {
        formatter.string(for: now.addingTimeInterval(-secondsAgo), relativeTo: now)
    }

    /// The named presentation is what turns the awkward ends of the scale into words: a note
    /// saved a second ago reads "now" rather than "1 second ago", and yesterday's is named
    /// rather than counted in hours.
    @Test(
        arguments: [
            (TimeInterval(0), "now"),
            (30, "30 seconds ago"),
            (60, "1 minute ago"),
            (300, "5 minutes ago"),
            (3600, "1 hour ago"),
            (10800, "3 hours ago"),
            (90000, "yesterday"),
            (172_800, "2 days ago"),
            (691_200, "last week")
        ])
    func namedRelativeWording(secondsAgo: TimeInterval, expected: String) {
        #expect(string(secondsAgo: secondsAgo) == expected)
    }

    /// The label only ever describes the past, so a note stamped in the future — a clock
    /// change, or a store copied from a machine running ahead — must still read sanely
    /// rather than as an empty or nonsense string.
    @Test func futureTimestampsReadForwards() {
        #expect(string(secondsAgo: -300) == "in 5 minutes")
    }

    /// The bar re-renders against a moving `now`; the same date has to age with it. This is
    /// what `RelativeTimeTicker` buys, so it is worth pinning that the reference date is
    /// honoured at all rather than quietly ignored in favour of the real current time.
    @Test func theSameDateAgesAsNowMovesOn() {
        let edited = now.addingTimeInterval(-60)

        #expect(formatter.string(for: edited, relativeTo: now) == "1 minute ago")
        #expect(formatter.string(for: edited, relativeTo: now.addingTimeInterval(240)) == "5 minutes ago")
    }
}
