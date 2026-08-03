import Foundation

/// Thrown by `waitUntil` when the condition never becomes true within the timeout.
///
/// Failing by *throwing* — rather than recording an `Issue` and returning — stops the test
/// at the wait. Otherwise the assertions that follow run against a value that was never
/// written and fail a second time with an unrelated message: unwritten `rtfData` is empty,
/// and `NSAttributedString(data:options:documentAttributes:)` reports empty RTF as
/// "Code=256 The file couldn't be opened", which reads like a serialization bug rather than
/// a wait that expired.
struct ConditionTimeout: Error, CustomStringConvertible {
    let condition: String
    let timeout: Duration

    var description: String { "timed out after \(timeout) waiting for \(condition)" }
}

/// Polls `isSatisfied` on the main actor until it holds, or throws `ConditionTimeout`.
///
/// Debounced work can only be observed by waiting for it, but sleeping a flat interval
/// just past the debounce turns the assertion into a race against process warm-up and
/// CPU contention — the margin is whatever headroom was hardcoded, typically tens of
/// milliseconds. Polling to a generous deadline removes the race without slowing the
/// happy path: the common case still returns within one poll interval of the work
/// landing, and only a genuine failure pays the full timeout.
///
/// A free function rather than a method: Swift Testing suites are plain types with no
/// shared base class to extend, and this never needed anything from the test case anyway.
@MainActor
func waitUntil(
    _ condition: String,
    timeout: Duration = .seconds(5),
    pollInterval: Duration = .milliseconds(10),
    isSatisfied: @MainActor () -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while !isSatisfied() {
        guard ContinuousClock.now < deadline else {
            throw ConditionTimeout(condition: condition, timeout: timeout)
        }
        try await Task.sleep(for: pollInterval)
    }
}
