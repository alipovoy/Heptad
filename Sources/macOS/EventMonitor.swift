import Cocoa

/// A utility class that encapsulates the lifecycle of an NSEvent monitor.
/// Adheres to RAII principles: the monitor is unregistered automatically on deinit.
///
/// Main-actor isolated: `NSEvent`'s monitor registration is AppKit, and the handler is called
/// on the main thread by both the local and the global variant.
@MainActor
class EventMonitor {
    /// The opaque token `NSEvent` hands back, `nonisolated(unsafe)` so `deinit` can give it
    /// up. `Any?` is not Sendable, which under the Swift 6 language mode puts it out of reach
    /// of a nonisolated `deinit` — and `deinit` is where the teardown has to happen. Every
    /// other access is through the isolated methods below, and by `deinit` no other reference
    /// to this object exists.
    nonisolated(unsafe) private var monitor: Any?
    private let mask: NSEvent.EventTypeMask
    private let isLocal: Bool
    private let handler: (NSEvent) -> NSEvent?

    /// Initializes a new event monitor but does not start it.
    /// - Parameters:
    ///   - local: If true, monitors local events. If false, monitors global events.
    ///   - mask: The types of events to monitor.
    ///   - handler: The closure to execute when an event is received.
    init(local: Bool, mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> NSEvent?) {
        self.isLocal = local
        self.mask = mask
        self.handler = handler
    }

    /// Starts the event monitor if it is not already running.
    func start() {
        guard monitor == nil else { return }
        if isLocal {
            monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: handler)
        } else {
            monitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
                _ = self?.handler(event)
            }
        }
    }

    /// Stops the event monitor.
    func stop() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    /// The RAII teardown, inlined rather than calling `stop()`.
    ///
    /// A `deinit` is nonisolated, so it cannot call the isolated `stop()` above at all, and
    /// `MainActor.assumeIsolated` would be an assumption rather than a fact — the last
    /// reference can be dropped on any thread. `isolated deinit` is the feature for exactly
    /// this and is deliberately *not* used: it emits an unguarded call to
    /// `swift_task_deinitOnExecutor`, the compiler raises no availability diagnostic even
    /// below this project's macOS 14 target, and a runtime missing that symbol fails at load
    /// rather than at the call. See #88 — it becomes the right answer once the deployment
    /// target rises.
    ///
    /// Inlining changes nothing about which thread this runs on: the class was unisolated
    /// before, so `deinit` reached `NSEvent.removeMonitor` from wherever the release landed
    /// then too. Every other path is now main-actor checked, which it was not.
    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
