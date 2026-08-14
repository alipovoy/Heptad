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

    /// Typing without a pause still reaches the store.
    ///
    /// Every keystroke restarts the debounce and nothing bounded how often, so at the production
    /// interval fifty characters over three seconds produced zero writes: the paragraph existed
    /// only in the text view, and a crash took all of it. The debounce here is longer than the
    /// test could ever wait, so only the ceiling can satisfy this.
    @Test func aBurstOfTypingIsWrittenAtTheCeiling() async throws {
        let note = NoteItem(id: 0)
        let center = NotificationCenter()
        let saver = NoteContentSaver(
            note: note, debounce: .seconds(30), maxDelay: .milliseconds(200),
            notificationCenter: center)

        let typing = Task { @MainActor in
            for length in 1...100 {
                saver.save(text: String(repeating: "a", count: length))
                try await Task.sleep(for: .milliseconds(20))
            }
        }
        defer { typing.cancel() }

        try await waitUntil("the ceiling to write the note mid-burst") { note.text.isEmpty == false }
    }

    /// And the ceiling is a ceiling, not a period: a pause resets it, so an idle editor is not
    /// writing to the store on a timer.
    @Test func theCeilingStartsAgainAfterASave() async throws {
        let note = NoteItem(id: 0)
        let center = NotificationCenter()
        let saver = NoteContentSaver(
            note: note, debounce: .milliseconds(50), maxDelay: .milliseconds(200),
            notificationCenter: center)

        saver.save(text: "first")
        try await waitUntil("the debounced save to write the note") { note.text.isEmpty == false }

        // Well past the ceiling measured from the first keystroke, so a burst clock that was
        // never reset would fire this one immediately instead of debouncing it.
        try await Task.sleep(for: .milliseconds(250))
        saver.save(text: "second")

        #expect(note.text == "first")
        try await waitUntil("the second save to land") { note.text == "second" }
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
