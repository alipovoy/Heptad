import Foundation
import Testing

/// A `UserDefaults` suite scoped to one test, cleaned up automatically when it is deallocated.
///
/// Half the suites in this target need `UserDefaults` for something they own — a manager under
/// test reads or writes it — and every one of them needs a scratch suite rather than `.standard`,
/// since a killed run must never leave state behind in the real app's defaults. Before this type
/// existed each suite rolled that out by hand: a `suiteName` built from a UUID, `#require` on
/// `UserDefaults(suiteName:)`, and a `deinit` that called `removePersistentDomain`. Rolling it up
/// here means a suite that forgets the `deinit` no longer leaks a domain — there is nothing left
/// to forget.
///
/// A class rather than a struct: the whole point is a `deinit`, which only a reference type gets.
final class ScratchDefaults {
    let defaults: UserDefaults
    private let suiteName: String

    /// `name` is folded into the suite name purely so a domain left behind by a crash (rather
    /// than a normal `deinit`) is still traceable to whichever suite wrote it; the UUID is what
    /// actually keeps concurrent and repeated test runs from colliding on the same domain.
    init(name: String) throws {
        suiteName = "\(name).\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
