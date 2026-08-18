import Foundation
import Testing

@testable import Heptad

/// What the banner is told, once the app is running. `StoreOpeningTests` covers the health a
/// launch starts on; this covers the writes that fail after it.
@MainActor
struct StoreStatusTests {

    @Test func aFailedSaveTurnsAHealthyStoreIntoAWarning() {
        let status = StoreStatus()
        #expect(status.health == .healthy)

        status.writeFailed(CocoaError(.fileWriteOutOfSpace))

        #expect(status.health == .notSaving)
    }

    /// Latched on purpose: the text the failed save was carrying is gone whether or not the next
    /// one lands, and the user still has to copy their notes out. See `StoreStatus.writeFailed`.
    @Test func aLaterSuccessDoesNotClearTheWarning() {
        let status = StoreStatus(.notSaving)

        status.writeFailed(CocoaError(.fileWriteOutOfSpace))

        #expect(status.health == .notSaving)
    }

    /// The in-memory stand-in is the worse diagnosis — nothing it holds outlives the session, so
    /// a failed write must not soften it into "will not take changes".
    @Test func anEphemeralStoreIsNotDowngradedByAFailedSave() {
        let status = StoreStatus(.ephemeral)

        status.writeFailed(CocoaError(.fileWriteOutOfSpace))

        #expect(status.health == .ephemeral)
    }
}
