import Foundation
import Testing

@testable import Heptad

/// The ticker exists so the edit-time label ages while the window sits open, and stops dead
/// when it does not. Both halves are asserted here; the intervals are milliseconds rather
/// than the production 30 seconds so the tests observe a real tick instead of mocking one.
@MainActor
struct RelativeTimeTickerTests {

    /// A fresh ticker has nothing to stop yet, and stopping it anyway — optional chaining on a
    /// nil task — has to be harmless rather than crash.
    @Test func startsStoppedAndStoppingBeforeStartingIsHarmless() {
        let ticker = RelativeTimeTicker(interval: .seconds(30))

        #expect(ticker.isRunning == false, "Nothing is on screen yet — a fresh ticker must not tick")

        ticker.stop()

        #expect(ticker.isRunning == false)
    }

    @Test func tickingMovesNowOn() async throws {
        let ticker = RelativeTimeTicker(interval: .milliseconds(20))
        let initial = ticker.now

        ticker.start()

        try await waitUntil("the ticker to publish a later instant") { ticker.now > initial }
    }

    /// The acceptance criterion from the issue: no timer runs behind a hidden window. Observed
    /// as "`now` stops moving", which is the only thing a caller can see — and the only thing
    /// that matters, since a task that kept running would keep waking the app.
    @Test func stoppingHaltsTheTicks() async throws {
        let ticker = RelativeTimeTicker(interval: .milliseconds(20))
        ticker.start()
        let started = ticker.now
        try await waitUntil("the first tick") { ticker.now > started }

        ticker.stop()
        let afterStopping = ticker.now
        // Long enough for several intervals to have elapsed had the task survived cancellation.
        try await Task.sleep(for: .milliseconds(120))

        #expect(ticker.isRunning == false)
        #expect(ticker.now == afterStopping, "A stopped ticker must not still be waking the app")
    }

    /// `start()` is called from every visibility signal, and on iOS `scenePhase` can report
    /// active more than once without an intervening background. A second start must not leave
    /// two tasks behind, since `stop()` only cancels the one it is holding.
    @Test func startingTwiceLeavesOneTicker() async throws {
        let ticker = RelativeTimeTicker(interval: .milliseconds(20))

        ticker.start()
        ticker.start()
        let started = ticker.now
        try await waitUntil("a tick from the running ticker") { ticker.now > started }

        ticker.stop()
        let afterStopping = ticker.now
        try await Task.sleep(for: .milliseconds(120))

        #expect(ticker.now == afterStopping, "A second start orphaned a task that stop() cannot reach")
    }

    /// Re-showing a window that was hidden for a while has to be right immediately: waiting a
    /// full interval to correct a badly stale label is exactly the bug this avoids.
    @Test func startingRereadsTheClockBeforeTheFirstTick() {
        let stale = Date(timeIntervalSinceReferenceDate: 0)
        let ticker = RelativeTimeTicker(interval: .seconds(30), now: stale)

        ticker.start()
        defer { ticker.stop() }

        #expect(ticker.now > stale, "The clock must be re-read on start, not one interval later")
    }
}
