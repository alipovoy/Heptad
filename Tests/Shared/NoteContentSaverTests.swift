import Foundation
import Testing

@testable import Heptad

@MainActor
struct NoteContentSaverTests {

    /// Three edits in a row leave the note holding the last one.
    ///
    /// Named for what is actually observable. `save` overwrites a single pending slot, so
    /// dropping the internal `saveTask?.cancel()` would still produce this result — the
    /// cancellation is an optimisation with no public surface, and pinning it would mean
    /// adding a seam to production code purely to watch an implementation detail.
    @Test func lastSaveWins() async throws {
        let note = NoteItem(id: 0)
        let center = NotificationCenter()
        let saver = NoteContentSaver(note: note, debounce: .milliseconds(150), notificationCenter: center)

        saver.save(text: "A")
        saver.save(text: "AB")
        saver.save(text: "ABC")

        // Poll to a deadline rather than sleeping a fixed interval past the debounce — see
        // `waitUntil`. Reaching the next line already proves the save landed.
        try await waitUntil("the debounced save to write the note") { note.text.isEmpty == false }

        #expect(note.text == "ABC")
    }

    /// Whitespace-only content stores as the empty string, so it never reaches the note.
    ///
    /// Which whitespace variants count as blank is `NoteItemTests.storedTextIsEmptyForBlankContent`'s
    /// rule to pin; one case here is enough to prove the saver honours it.
    ///
    /// `flush` rather than a sleep: there is no state transition to poll for here — the
    /// assertion is that nothing was written — so only a synchronous write makes the test
    /// capable of failing at all. Asserting straight after `save` would pass for any
    /// implementation, including one that dropped the whitespace check entirely.
    @Test func blankContentStoresNothing() {
        let note = NoteItem(id: 0)
        let center = NotificationCenter()
        let saver = NoteContentSaver(note: note, debounce: .seconds(5), notificationCenter: center)

        saver.save(text: "   \n  ")
        center.post(name: .flushPendingSaves, object: nil)

        #expect(note.text.isEmpty)
    }

    /// Wiping a note's text wipes what is stored. The only path where a bug loses user content
    /// outright, so it is worth pinning: `storedText(from:)` returns "", which differs from what
    /// is stored, so the unchanged-text guard lets the write through.
    @Test func clearingContentWipesTheNote() throws {
        let note = NoteItem(id: 0, modifiedAt: .distantPast)
        let center = NotificationCenter()
        let saver = NoteContentSaver(note: note, debounce: .seconds(5), notificationCenter: center)

        saver.save(text: "Some content")
        center.post(name: .flushPendingSaves, object: nil)
        try #require(note.text.isEmpty == false)
        let firstEdit = note.modifiedAt

        let beforeClearing = Date.now
        saver.save(text: "   \n  ")
        center.post(name: .flushPendingSaves, object: nil)

        #expect(note.text.isEmpty)
        #expect(note.modifiedAt >= beforeClearing)
        #expect(note.modifiedAt > firstEdit)
    }

    @Test func saveUpdatesModifiedAt() async throws {
        let note = NoteItem(id: 0, modifiedAt: .distantPast)
        let center = NotificationCenter()
        let saver = NoteContentSaver(note: note, debounce: .milliseconds(50), notificationCenter: center)

        let before = Date.now
        saver.save(text: "Edited")
        try await waitUntil("the debounced save to write the note") { note.text.isEmpty == false }

        #expect(note.modifiedAt >= before)
        #expect(note.modifiedAt <= .now)
    }

    @Test func unchangedContentLeavesModifiedAtAlone() async throws {
        let note = NoteItem(id: 0)
        let center = NotificationCenter()
        let saver = NoteContentSaver(note: note, debounce: .milliseconds(50), notificationCenter: center)

        saver.save(text: "Same")
        try await waitUntil("the debounced save to write the note") { note.text.isEmpty == false }
        let firstEdit = note.modifiedAt

        // Re-saving identical content — what reopening or switching back to a note does —
        // short-circuits on the unchanged-data guard, so the timestamp must not move.
        // `flush` forces the second save through synchronously; waiting cannot prove an
        // absence, and a flat sleep only makes the wait long enough to feel convincing.
        saver.save(text: "Same")
        center.post(name: .flushPendingSaves, object: nil)

        #expect(note.modifiedAt == firstEdit)
    }

    @Test func flushImmediatelySavesPending() {
        let note = NoteItem(id: 0)
        let center = NotificationCenter()
        let saver = NoteContentSaver(note: note, debounce: .seconds(5), notificationCenter: center)

        saver.save(text: "Flushed Text")

        // The save is debounced so the note should not have it yet
        #expect(note.text.isEmpty)

        center.post(name: .flushPendingSaves, object: nil)

        // The save should have happened synchronously on the main thread now
        #expect(note.text == "Flushed Text")
    }
}
