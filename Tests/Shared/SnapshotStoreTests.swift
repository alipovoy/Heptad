import Foundation
import Testing

@testable import Heptad

/// Rotating local snapshots, against a temporary directory so nothing here touches the real
/// Application Support folder.
@MainActor
final class SnapshotStoreTests {
    private let directory: URL
    private let store: SnapshotStore

    init() throws {
        directory = URL.temporaryDirectory.appending(path: "SnapshotStoreTests.\(UUID())")
        store = SnapshotStore(directory: directory)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    private func notes(_ contents: [Int: String] = [0: "user: admin"]) throws -> [NoteItem] {
        try (0..<AppConstants.noteCount).map { id in
            let data =
                try contents[id].map {
                    try #require(NoteItem.rtfData(from: NSAttributedString(string: $0)))
                } ?? Data()
            return NoteItem(id: id, rtfData: data)
        }
    }

    private func fileCount() -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path()).count) ?? 0
    }

    // MARK: - Writing

    @Test func writingStoresEverySevenNotes() throws {
        #expect(store.writeIfDue(notes: try notes()))

        let stored = try #require(store.snapshots().first)
        #expect(stored.notes.count == AppConstants.noteCount)
        #expect(stored.notes.first { !$0.rtfData.isEmpty }?.id == 0)
    }

    /// The interval is a floor on how often the app snapshots itself while running.
    @Test func aSecondSnapshotWaitsOutTheInterval() throws {
        let notes = try notes()
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

        #expect(store.writeIfDue(notes: notes, now: start))

        notes[1].rtfData = try #require(NoteItem.rtfData(from: NSAttributedString(string: "later")))

        #expect(store.writeIfDue(notes: notes, now: start.addingTimeInterval(60)) == false)
        #expect(
            store.writeIfDue(notes: notes, now: start.addingTimeInterval(SnapshotStore.minimumInterval)))
        #expect(store.snapshots().count == 2)
    }

    /// `force` is what termination uses — but not a licence to write copies.
    @Test func forcingSkipsASnapshotThatWouldBeIdentical() throws {
        let notes = try notes()
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

        #expect(store.writeIfDue(notes: notes, now: now, force: true))
        #expect(store.writeIfDue(notes: notes, now: now, force: true) == false)

        #expect(store.snapshots().count == 1)
    }

    /// The same instant on purpose: two forced writes in one millisecond is reachable when a
    /// scene phase change and a termination arrive together, and the second must not overwrite
    /// the first.
    @Test(.bug(id: 85)) func forcingWritesWhenTheNotesHaveChanged() throws {
        let notes = try notes()
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        #expect(store.writeIfDue(notes: notes, now: now, force: true))

        notes[0].rtfData = Data()

        #expect(store.writeIfDue(notes: notes, now: now, force: true))
        #expect(store.snapshots().count == 2)
    }

    /// Collided names must still sort newest first — the property that decides what
    /// `mostRecent()` returns and which end `rotate()` drops.
    ///
    /// Suffixing the second file instead of moving its stamp would invert exactly this and
    /// leave the count above unchanged: `-` precedes the `.` of `.json`, so `-2` sorts *below*
    /// the name it was meant to follow. The last millisecond of a second, so the nudges have to
    /// carry through the second as well.
    @Test(.bug(id: 85)) func collidedSnapshotsStillSortNewestFirst() throws {
        let notes = try notes()
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000).addingTimeInterval(0.999)

        for step in 0..<3 {
            notes[0].rtfData = try #require(
                NoteItem.rtfData(from: NSAttributedString(string: "step \(step)")))
            #expect(store.writeIfDue(notes: notes, now: now, force: true))
        }

        #expect(fileCount() == 3)

        let listed = store.snapshots()
        #expect(listed.count == 3)
        #expect(listed.first?.notes.first?.rtfData == notes[0].rtfData, "Newest first")
    }

    // MARK: - Rotation

    @Test func onlyTheMostRecentSnapshotsAreKept() throws {
        let notes = try notes()
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

        // One more than the cap, each a minute apart and each different, so none is skipped.
        for step in 0...SnapshotStore.keep {
            notes[0].rtfData = try #require(
                NoteItem.rtfData(from: NSAttributedString(string: "step \(step)")))
            store.writeIfDue(notes: notes, now: start.addingTimeInterval(Double(step) * 60), force: true)
        }

        #expect(fileCount() == SnapshotStore.keep)
        let kept = store.snapshots()
        #expect(kept.count == SnapshotStore.keep)
        #expect(kept.first?.createdAt ?? .distantPast > kept.last?.createdAt ?? .distantFuture,
                "Newest first")
    }

    // MARK: - Reading

    @Test func snapshotsAreListedNewestFirst() throws {
        let notes = try notes()
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

        for step in 0..<3 {
            notes[0].rtfData = try #require(
                NoteItem.rtfData(from: NSAttributedString(string: "step \(step)")))
            store.writeIfDue(notes: notes, now: start.addingTimeInterval(Double(step) * 60), force: true)
        }

        let listed = store.snapshots()

        #expect(listed.count == 3)
        #expect(listed.map(\.createdAt) == listed.map(\.createdAt).sorted(by: >))
    }

    /// A corrupt file must not hide the good ones — the whole point is being recoverable.
    @Test func anUnreadableSnapshotIsSkipped() throws {
        store.writeIfDue(notes: try notes(), force: true)
        try Data("not json".utf8).write(to: directory.appending(path: "snapshot-99999999T000000Z.json"))

        #expect(store.snapshots().count == 1)
    }

    @Test func noSnapshotsWhenNothingHasBeenWritten() {
        #expect(store.snapshots().isEmpty)
    }

    // MARK: - Restoring

    @Test func restoringPutsEveryNoteBack() throws {
        let notes = try notes([0: "before", 3: "checklist"])
        notes[0].isPlainText = true
        store.writeIfDue(notes: notes, force: true)
        let snapshot = try #require(store.snapshots().first)

        for note in notes {
            note.rtfData = Data()
            note.isPlainText = false
        }

        store.restore(snapshot, into: notes)

        #expect(notes[0].attributedContent?.string == "before")
        #expect(notes[3].attributedContent?.string == "checklist")
        #expect(notes[1].isEmpty)
        #expect(notes[0].isPlainText)
    }

    /// Ids the snapshot never knew about are left alone rather than emptied.
    @Test func restoringLeavesNotesTheSnapshotDoesNotMention() throws {
        let stored = NoteSnapshot(notes: Array(try notes([0: "only this one"]).prefix(1)))
        let live = try notes([2: "untouched"])

        store.restore(stored, into: live)

        #expect(live[0].attributedContent?.string == "only this one")
        #expect(live[2].attributedContent?.string == "untouched")
    }
}
