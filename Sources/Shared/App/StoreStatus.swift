import Foundation
import Observation
import OSLog

/// How the note store is behaving, and the reason the app can say so on screen.
///
/// Every case below leaves seven notes in an editor that looks entirely normal, which is what
/// makes this worth a type: without one, the only trace a failure leaves is a line in the log.
enum StoreHealth: Equatable {
    /// The store on disk opened and every write to it has landed.
    case healthy

    /// The store opened, but a write to it failed. The notes on screen are the user's own — they
    /// were read from the file — and the changes to them are going nowhere.
    case notSaving

    /// The store could not be opened at all. The notes on screen are blank stand-ins held in
    /// memory, and the session ends with them.
    case ephemeral
}

/// The store's health as the views see it.
///
/// A type rather than a value passed down at launch, for the reason `WindowState` is one:
/// observation is what puts the banner on screen the moment a save fails, and a save can fail
/// long after launch. `HeptadApp` decides the opening health; `ContentView` reports the writes
/// that follow.
@MainActor
@Observable
final class StoreStatus {
    private(set) var health: StoreHealth

    init(_ health: StoreHealth = .healthy) {
        self.health = health
    }

    /// Records a save that did not land.
    ///
    /// Latched: a store that lost one save is not made trustworthy by taking the next, and the
    /// text the failed save was carrying is gone either way. Clearing the warning because the disk
    /// briefly freed up would take the notice away from the user who still has to copy their notes
    /// out. Only a relaunch resets it, which is also the only thing that can fix the cause.
    ///
    /// `.ephemeral` is the worse diagnosis and stays: an in-memory store never claimed to save.
    func writeFailed(_ error: Error) {
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "Heptad", category: "store")
            .error("A save to the note store failed: \(error)")

        guard health == .healthy else { return }
        health = .notSaving
    }
}
