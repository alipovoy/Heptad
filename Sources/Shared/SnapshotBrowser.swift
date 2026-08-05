import SwiftUI

/// The list-and-restore half of local snapshots: pick a moment, put all seven notes back to it.
///
/// Deliberately not a version browser — no per-note history, no diffing, no previews beyond
/// the first line of each note that had one.
struct SnapshotBrowser: View {
    let snapshots: [NoteSnapshot]
    let restore: (NoteSnapshot) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Confirms before overwriting, because restoring replaces every note at once.
    @State private var pendingRestore: NoteSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            if snapshots.isEmpty {
                Text("No snapshots yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(snapshots, id: \.createdAt) { snapshot in
                    row(for: snapshot)
                }
                .listStyle(.plain)
            }
        }
        .frame(minWidth: 320, minHeight: 260)
        .confirmationDialog(
            "Restore all seven notes to this snapshot?",
            isPresented: .init(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
            titleVisibility: .visible
        ) {
            Button("Restore", role: .destructive) {
                if let pendingRestore {
                    restore(pendingRestore)
                }
                dismiss()
            }
            Button("Cancel", role: .cancel) { pendingRestore = nil }
        } message: {
            Text("Anything currently in the notes is replaced.")
        }
    }

    private var header: some View {
        HStack {
            Text("Snapshots").font(.headline)
            Spacer()
            Button("Done") { dismiss() }
        }
        .padding(12)
    }

    private func row(for snapshot: NoteSnapshot) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.createdAt.formatted(date: .abbreviated, time: .shortened))
                Text(summary(of: snapshot))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Restore") { pendingRestore = snapshot }
                .buttonStyle(.bordered)
        }
        .padding(.vertical, 2)
    }

    /// How much was in the notes at the time, which is the only thing that tells two
    /// snapshots apart at a glance.
    private func summary(of snapshot: NoteSnapshot) -> String {
        let used = snapshot.notes.count { !$0.rtfData.isEmpty }
        return used == 1 ? "1 note with content" : "\(used) notes with content"
    }
}

#Preview("Snapshots") {
    SnapshotBrowser(
        snapshots: (0..<3).map {
            NoteSnapshot(
                createdAt: PreviewFixtures.now.addingTimeInterval(Double($0) * -3600),
                notes: PreviewFixtures.notes())
        },
        restore: { _ in }
    )
}

#Preview("No snapshots") {
    SnapshotBrowser(snapshots: [], restore: { _ in })
}
