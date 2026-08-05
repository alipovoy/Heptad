import Foundation
import OSLog

/// A copy of all seven notes at one moment.
///
/// JSON, with the RTF as `Data` — which `JSONEncoder` writes as base64. The format is
/// deliberately dull: this is a safety net for an accidental clear, and it has to stay
/// readable by a future version that has forgotten everything about today's code.
struct NoteSnapshot: Codable, Equatable {
    struct Note: Codable, Equatable {
        let id: Int
        let rtfData: Data
        let modifiedAt: Date
        let isPlainText: Bool
    }

    let createdAt: Date
    let notes: [Note]

    /// Whether this holds the same notes as `other`, timestamps aside.
    ///
    /// Deliberately not `==`: `modifiedAt` is written to JSON as ISO 8601, which keeps whole
    /// seconds only, so a snapshot never compares equal to the live notes it was made from.
    /// What "nothing has changed" means here is the text and the modes.
    func hasSameContent(as other: Self) -> Bool {
        notes.count == other.notes.count
            && zip(notes, other.notes).allSatisfy {
                $0.id == $1.id && $0.rtfData == $1.rtfData && $0.isPlainText == $1.isPlainText
            }
    }

    init(createdAt: Date = .now, notes: [NoteItem]) {
        self.createdAt = createdAt
        self.notes = notes.map {
            Note(
                id: $0.id, rtfData: $0.rtfData, modifiedAt: $0.modifiedAt,
                isPlainText: $0.isPlainText)
        }
    }
}

/// Rotating local snapshots of the notes, in Application Support.
///
/// Not a user-facing folder and not a sync target: it needs no entitlements, lives inside the
/// sandbox container, and exists only so that a clear or a bad paste is recoverable. A full
/// version browser is a different feature.
@MainActor
final class SnapshotStore {
    /// How many snapshots are kept. Oldest first out.
    static let keep = 20

    /// The floor on how often a snapshot is taken while the app runs.
    static let minimumInterval: TimeInterval = 10 * 60

    private static let logger = Logger(subsystem: "dev.lipovoy.heptad", category: "snapshots")

    private let directory: URL
    private let fileManager: FileManager

    /// When the last snapshot was written this session, for the interval above. Not persisted:
    /// one extra snapshot per launch is a fair price for not storing a clock anywhere.
    private var lastWriteAt: Date?

    /// - Parameter directory: overridden by tests; otherwise Application Support/Snapshots.
    init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directory =
            directory
            ?? URL.applicationSupportDirectory.appending(path: "Snapshots", directoryHint: .isDirectory)
    }

    // MARK: - Writing

    /// Writes a snapshot unless one was taken recently, or unless nothing has changed since
    /// the last one. Returns whether it wrote.
    ///
    /// The unchanged check is what keeps the twenty slots meaningful: without it, opening and
    /// closing the window a few times would push every real snapshot out with copies.
    @discardableResult
    func writeIfDue(notes: [NoteItem], now: Date = .now, force: Bool = false) -> Bool {
        if !force, let lastWriteAt, now.timeIntervalSince(lastWriteAt) < Self.minimumInterval {
            return false
        }

        let snapshot = NoteSnapshot(createdAt: now, notes: notes)
        if let previous = mostRecent(), snapshot.hasSameContent(as: previous) {
            lastWriteAt = now
            return false
        }

        do {
            try write(snapshot)
            lastWriteAt = now
            return true
        } catch {
            // A failed snapshot is not worth interrupting anyone over: the notes themselves
            // are safe in the store, and this is the belt to that pair of braces.
            Self.logger.error("Could not write snapshot: \(error.localizedDescription)")
            return false
        }
    }

    private func write(_ snapshot: NoteSnapshot) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: url(for: snapshot.createdAt), options: .atomic)

        rotate()
    }

    /// Named so that a plain lexicographic sort is a sort by age.
    ///
    /// Down to the millisecond, then nudged forward a millisecond at a time until the name is
    /// free: two forced snapshots — a scene phase change and a termination — can land in the
    /// same millisecond, and two files of the same name is one snapshot silently overwriting
    /// another. The stamp only has to sort; `createdAt` inside the file is the real date.
    ///
    /// Nudging rather than suffixing is what keeps the sort honest. A `-2` on the second file
    /// would sort *below* the first, because `-` precedes the `.` of `.json`; a later stamp of
    /// the same width always sorts above.
    private func url(for date: Date) -> URL {
        var date = date
        var url = fileURL(for: date)
        while fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
            date.addTimeInterval(0.001)
            url = fileURL(for: date)
        }
        return url
    }

    private func fileURL(for date: Date) -> URL {
        let stamp = date.ISO8601Format(
            .iso8601(timeZone: .gmt)
                .dateSeparator(.omitted)
                .timeSeparator(.omitted)
                .time(includingFractionalSeconds: true))
        return directory.appending(
            path: "snapshot-\(stamp.replacingOccurrences(of: ".", with: "")).json")
    }

    private func rotate() {
        let files = snapshotFiles()
        guard files.count > Self.keep else { return }

        for file in files.dropFirst(Self.keep) {
            try? fileManager.removeItem(at: file)
        }
    }

    // MARK: - Reading

    /// Every stored snapshot, newest first. Unreadable files are skipped rather than thrown:
    /// one corrupt snapshot must not hide the nineteen good ones.
    func snapshots() -> [NoteSnapshot] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return snapshotFiles().compactMap { file in
            guard let data = try? Data(contentsOf: file) else { return nil }
            return try? decoder.decode(NoteSnapshot.self, from: data)
        }
    }

    private func mostRecent() -> NoteSnapshot? {
        guard let newest = snapshotFiles().first, let data = try? Data(contentsOf: newest) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(NoteSnapshot.self, from: data)
    }

    /// Newest first, by the timestamp in the name.
    private func snapshotFiles() -> [URL] {
        let files =
            (try? fileManager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("snapshot-") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    // MARK: - Restoring

    /// Puts `snapshot` back into `notes`, matching them up by id.
    ///
    /// Notes the snapshot does not mention are left alone rather than emptied — a snapshot
    /// from a version with fewer notes must not wipe the ones it never knew about.
    func restore(_ snapshot: NoteSnapshot, into notes: [NoteItem]) {
        let byId = Dictionary(uniqueKeysWithValues: snapshot.notes.map { ($0.id, $0) })

        for note in notes {
            guard let stored = byId[note.id] else { continue }
            note.rtfData = stored.rtfData
            note.modifiedAt = stored.modifiedAt
            note.isPlainText = stored.isPlainText
        }
    }
}
