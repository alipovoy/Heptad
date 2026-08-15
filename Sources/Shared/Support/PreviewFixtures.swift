import Foundation
import SwiftData

/// Sample data for the `#Preview` blocks.
///
/// Deliberately not `HeptadApp.sharedModelContainer`: that one opens the real store and
/// calls `fatalError` if it cannot, neither of which a preview should be doing.
///
/// Deliberately not behind `#if DEBUG` either. `#Preview` expands into a type the compiler
/// type-checks in every configuration, so a DEBUG-only fixture fails to resolve in Release
/// unless every preview is guarded too. Nothing here reaches the shipping binary regardless:
/// the linker strips the previews, and these fixtures with them.
enum PreviewFixtures {
    /// The anchor the `TextStatisticsBar` previews measure their edit times against, so
    /// the relative string is whatever they ask for rather than whatever today is.
    ///
    /// `ContentView`'s previews cannot use it — their anchor is the live ticker — so the
    /// notes below are stamped relative to the real clock instead.
    static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// A ticker parked at `now`, which is what the bar takes. Never started, so the previews
    /// measure against that anchor rather than drifting onto the real clock.
    @MainActor
    static func ticker() -> RelativeTimeTicker {
        RelativeTimeTicker(now: now)
    }

    /// Seven notes with a realistic mix: two with content, the rest never written to.
    static func notes() -> [NoteItem] {
        let content = [
            0: "Lab credentials\nuser: admin\npass: **rotate-me**",
            3: "Release checklist for the long-title case, truncated in the bar"
        ]
        return (0..<AppConstants.noteCount).map { id in
            let text = content[id]
            return NoteItem(
                id: id,
                text: text ?? "",
                modifiedAt: text == nil ? .distantPast : .now.addingTimeInterval(-300)
            )
        }
    }

    /// An in-memory container holding `notes()`, or nothing at all — which is what puts
    /// `ContentView` on its "Notes could not be loaded" branch.
    @MainActor
    static func container(seeded: Bool = true) -> ModelContainer {
        do {
            let container = try ModelContainer(
                for: NoteItem.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            if seeded {
                for note in notes() { container.mainContext.insert(note) }
            }
            return container
        } catch {
            fatalError("Preview container could not be created: \(error)")
        }
    }
}
