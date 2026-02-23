import Cocoa

/// A utility class that encapsulates the lifecycle of an NSEvent monitor.
/// Adheres to RAII principles: the monitor is unregistered automatically on deinit.
class EventMonitor {
    private var monitor: Any?
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

    deinit {
        stop()
    }
}
