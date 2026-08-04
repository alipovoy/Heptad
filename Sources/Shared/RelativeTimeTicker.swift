import Foundation

/// Publishes a coarse "now" so relative timestamps age in place — "now" becomes
/// "2 minutes ago" while the window just sits there.
///
/// Nothing else in the app re-renders on the passage of time, so the edit-time label needs a
/// clock of its own; the point of putting it behind an object is that the clock only runs
/// while there is someone to read it. Callers start and stop it from their own visibility
/// signal (`.windowDidBecomeVisible` / `.windowDidHide` on macOS, `scenePhase` on iOS), and
/// while stopped there is no task and no timer at all.
///
/// The interval is deliberately coarse: the label's smallest unit is a second, but waking the
/// app every second to keep "44 seconds ago" honest buys precision in the one range where the
/// answer the user actually wants ("did I write this just now, or last week?") is already clear.
@MainActor
@Observable
final class RelativeTimeTicker {
    /// The instant the labels format against. Re-read on `start()` and on every tick.
    private(set) var now: Date

    private let interval: Duration
    private var task: Task<Void, Never>?

    var isRunning: Bool { task != nil }

    init(interval: Duration = AppConstants.Timing.relativeTimeRefresh, now: Date = .now) {
        self.interval = interval
        self.now = now
    }

    /// `isolated` so the cancellation runs on the main actor, wherever the last release lands.
    isolated deinit {
        task?.cancel()
    }

    /// Re-reads the clock and keeps it current until `stop()`. Safe to call when already running.
    ///
    /// The immediate re-read is what makes a window that was hidden for an hour show the right
    /// label the moment it comes back, instead of the one it froze on plus a tick of lag.
    func start() {
        now = .now
        guard task == nil else { return }

        let interval = interval
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }
                now = .now
            }
        }
    }

    /// Stops ticking. `now` keeps its last value; `start()` refreshes it.
    func stop() {
        task?.cancel()
        task = nil
    }
}
