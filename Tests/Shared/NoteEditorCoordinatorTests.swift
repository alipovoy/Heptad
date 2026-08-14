import Foundation
import Testing

#if canImport(UIKit)
    import UIKit
#else
    import AppKit
#endif

@testable import Heptad

@MainActor
struct NoteEditorCoordinatorTests {

    private let coordinator = SpyEditorCoordinator()
    private let container = PlatformView()
    private let notes = [NoteItem(id: 0), NoteItem(id: 1)]

    // MARK: - Selection

    /// Re-selecting the note already on screen does nothing at all.
    ///
    /// SwiftUI drives `update` from view updates, so it is called far more often than the
    /// selection actually changes. What pins the early return specifically — rather than the
    /// view cache behind it — is `resignFocus`: without the return the showing view would be
    /// resigned, removed and re-added, which is a caret the user did not ask to lose.
    @Test func updatingToTheShowingNoteChangesNothing() throws {
        coordinator.setup(container: container, notes: notes, selectedIndex: 0)
        let showing = try #require(container.subviews.first)

        coordinator.update(notes: notes, selectedIndex: 0)

        #expect(coordinator.resignedViews.isEmpty)
        #expect(coordinator.madeViewNoteIds == [0])  // and so no second saver: same guard
        #expect(
            coordinator.configuredNoteIds == [0, 0],
            "but it is repainted: this is the only path a mode change on the showing note takes")
        #expect(container.subviews.count == 1)
        #expect(container.subviews.first === showing)
        #expect(container.constraints.count == 4)  // not pinned a second time either
    }

    /// Leaving a note and coming back shows the same view instance, not a rebuilt one.
    ///
    /// The cache is what makes a note keep its scroll position, selection and undo stack
    /// across a switch, none of which survive `makeEditorView` running again.
    @Test func switchingBackReusesTheCachedView() throws {
        coordinator.setup(container: container, notes: notes, selectedIndex: 0)
        let firstView = try #require(container.subviews.first)

        coordinator.update(notes: notes, selectedIndex: 1)
        coordinator.update(notes: notes, selectedIndex: 0)

        #expect(coordinator.madeViewNoteIds == [0, 1])
        #expect(coordinator.currentNoteId == 0)
        #expect(container.subviews.count == 1)
        #expect(container.subviews.first === firstView)
    }

    // MARK: - Applying the note's mode

    /// The note's mode is applied on the install path, not only on the early return for the note
    /// already showing.
    ///
    /// Before this, `makeEditorView` applied the mode at creation and `update` re-applied it only
    /// when the same note came round again — so a cached view whose note changed mode while it
    /// was off screen came back in the old one, and "apply the mode" existed twice per platform.
    @Test(.bug(id: 103))
    func everyInstalledViewIsConfiguredForItsNote() {
        coordinator.setup(container: container, notes: notes, selectedIndex: 0)
        coordinator.update(notes: notes, selectedIndex: 1)
        coordinator.update(notes: notes, selectedIndex: 0)  // the cached view coming back

        #expect(coordinator.configuredNoteIds == [0, 1, 0])
        #expect(coordinator.madeViewNoteIds == [0, 1], "Still only built once each")
    }

    /// A new view is built, then configured, then loaded — and the coordinator already names the
    /// incoming note by the time it is configured.
    ///
    /// Every step of that order is load-bearing. `configure` flattens what is already in the
    /// view, so running it before `load` is what leaves the note's own attributes intact.
    /// `configure` also reports its edit through `textDidChange`, which resolves the saver by the
    /// showing note — so with `currentNoteId` still naming the note being left, opening a plain
    /// note would write it over that one.
    @Test(.bug(id: 103))
    func aNewViewIsConfiguredBeforeItsContentIsLoaded() {
        coordinator.setup(container: container, notes: notes, selectedIndex: 1)

        #expect(coordinator.stepsInOrder == ["make", "configure(showing: 1)", "load"])
    }

    // MARK: - Appearance

    /// Each note is drawn in its own colour, and that colour is its *position* — not its id.
    ///
    /// This class is the only one that addresses a note by `id`; everything above it, the palette
    /// included, addresses one by position. The two agree only while the stored ids are exactly
    /// `0..<noteCount`, and `NotePalette.boldTint` clamps rather than fails — so where they came
    /// apart, bold text was drawn in another note's colour with nothing to say which.
    ///
    /// Sparse ids rather than `0, 1`, because with those every wrong answer is also the right one.
    @Test func eachNoteIsTintedByItsPositionRatherThanItsId() {
        let sparse = [NoteItem(id: 3), NoteItem(id: 9)]

        coordinator.setup(container: container, notes: sparse, selectedIndex: 0)
        coordinator.update(notes: sparse, selectedIndex: 1)

        #expect(coordinator.configuredAppearances.count == 2)
        #expect(coordinator.configuredAppearances.first?.boldTint == NotePalette.boldTint(forNoteIndex: 0))
        #expect(
            coordinator.configuredAppearances.last?.boldTint == NotePalette.boldTint(forNoteIndex: 1),
            "Note 9 is the second note, so it takes the second tint — not the clamped seventh")
    }

    // MARK: - Zoom

    /// A zoom step repaints every note that has a cached view, not only the one on screen.
    ///
    /// The zoom is app-wide and views are cached across switches, so a repaint scoped to the
    /// showing note would leave every other note drawn at the old size until it was next switched
    /// to — and `⌘+` is held down, so the stale notes would be the ones the user is not looking at
    /// while they change the size for the one they are.
    ///
    /// Driven through the coordinator's own seams rather than `.standard`/`.default`: with the
    /// defaults it reads and the centre it listens on both injected, this covers the whole path
    /// from the stored size to the repaint instead of stopping at the notification.
    @Test func aZoomStepRepaintsEveryCachedNote() throws {
        let scratch = try ScratchDefaults(name: "NoteEditorCoordinatorTests")
        let center = NotificationCenter()
        let zoomed = SpyEditorCoordinator(defaults: scratch.defaults, notificationCenter: center)

        zoomed.setup(container: container, notes: notes, selectedIndex: 0)
        zoomed.update(notes: notes, selectedIndex: 1)  // both notes now have a cached view
        let configuredBeforeTheStep = zoomed.configuredNoteIds.count

        EditorFontSize.step(increase: true, defaults: scratch.defaults, notificationCenter: center)

        let repainted = zoomed.configuredNoteIds.dropFirst(configuredBeforeTheStep)
        #expect(
            Set(repainted) == [0, 1],
            "Every cached note is repainted, not only the one on screen")
        #expect(
            zoomed.configuredAppearances.last?.fontSize == EditorFontSize.current(scratch.defaults),
            "and at the size that was just stored")
    }

    /// A step that changes nothing posts nothing, so there is no repaint to observe either —
    /// which is what keeps a held `⌘+` at the ceiling from restyling every cached note per
    /// keystroke.
    @Test func aZoomStepAtTheCeilingRepaintsNothing() throws {
        let scratch = try ScratchDefaults(name: "NoteEditorCoordinatorTests")
        let center = NotificationCenter()
        scratch.defaults.set(
            Double(AppConstants.Layout.maxFontSize), forKey: AppConstants.editorFontSizeKey)
        let zoomed = SpyEditorCoordinator(defaults: scratch.defaults, notificationCenter: center)

        zoomed.setup(container: container, notes: notes, selectedIndex: 0)
        let configuredBeforeTheStep = zoomed.configuredNoteIds.count

        EditorFontSize.step(increase: true, defaults: scratch.defaults, notificationCenter: center)

        #expect(zoomed.configuredNoteIds.count == configuredBeforeTheStep)
    }

    // MARK: - View swapping

    @Test func switchingAwayResignsAndRemovesTheOutgoingView() throws {
        coordinator.setup(container: container, notes: notes, selectedIndex: 0)
        let outgoing = try #require(container.subviews.first)

        coordinator.update(notes: notes, selectedIndex: 1)

        let resigned = try #require(coordinator.resignedViews.first)
        #expect(coordinator.resignedViews.count == 1)
        #expect(resigned.view === outgoing)
        #expect(resigned.superviewAtCall === container)  // resigned before removal, not after
        #expect(outgoing.superview == nil)
        #expect(container.subviews.count == 1)
        #expect(container.subviews.first !== outgoing)
    }

    /// The incoming view is pinned to all four container edges.
    ///
    /// Checked edge by edge because a missing pin does not fail loudly: the view still
    /// appears, just sized wrong, which is the kind of layout bug that only shows up once
    /// the container is resized. Autoresizing must also be off, or the constraints conflict.
    @Test(arguments: [
        NSLayoutConstraint.Attribute.leading, .trailing, .top, .bottom
    ])
    func incomingViewIsPinnedToTheContainerEdge(edge: NSLayoutConstraint.Attribute) throws {
        coordinator.setup(container: container, notes: notes, selectedIndex: 0)
        let editorView = try #require(container.subviews.first)

        #expect(editorView.translatesAutoresizingMaskIntoConstraints == false)
        #expect(Self.isPinned(editorView, to: container, on: edge))
    }

    /// A view returning to the container is pinned again, rather than relying on constraints
    /// that `removeFromSuperview` already dropped when it left.
    @Test func reusedViewIsPinnedAgainOnItsWayBack() throws {
        coordinator.setup(container: container, notes: notes, selectedIndex: 0)
        coordinator.update(notes: notes, selectedIndex: 1)
        coordinator.update(notes: notes, selectedIndex: 0)

        let editorView = try #require(container.subviews.first)
        #expect(container.constraints.count == 4)
        for edge in [NSLayoutConstraint.Attribute.leading, .trailing, .top, .bottom] {
            #expect(Self.isPinned(editorView, to: container, on: edge))
        }
    }

    // MARK: - Text routing

    /// Typing reaches the saver for the note on screen *now*, not the one that was showing
    /// before the switch — the bug this guards against writes one note's text into another's.
    @Test func textChangesRouteToTheShowingNotesSaver() async throws {
        coordinator.setup(container: container, notes: notes, selectedIndex: 0)
        coordinator.update(notes: notes, selectedIndex: 1)

        let typed = "Belongs to the second note"
        coordinator.plainTextByNoteId[notes[1].id] = typed
        coordinator.noteDidChange()

        // Poll to a deadline rather than sleeping past the 300 ms debounce: the flat sleep
        // races process warm-up and CPU contention for whatever margin was hardcoded.
        try await waitUntil("the second note's debounced save to write the note") {
            notes[1].text.isEmpty == false
        }

        // Reaching here already proves note 1 was written. Note 0 stays empty for the strong
        // reason, not a timing one: its saver was never handed anything to write, and had the
        // text gone there instead this wait would have expired rather than fallen through.
        #expect(notes[0].text.isEmpty)
    }

    /// Text arriving before any `setup` is dropped instead of crashing.
    ///
    /// Not hypothetical on macOS: `NSTextView` delegate callbacks can fire while the editor is
    /// being torn down and rebuilt, when there is no current note and no saver to route to.
    @Test func textDidChangeBeforeSetupIsIgnored() async {
        coordinator.plainTextByNoteId[0] = "Typed into nothing"
        coordinator.noteDidChange()

        #expect(coordinator.currentNoteId == nil)
        #expect(notes[0].text.isEmpty)
        #expect(notes[1].text.isEmpty)

        // Statistics are the one observable side effect past the guard, and they arrive on a
        // detached task. Draining a task of the same priority gives a missing guard a chance to
        // report before the count is read.
        await Task.detached(priority: .utility) {}.value
        #expect(coordinator.reportedStats.isEmpty)
    }

    // MARK: - Statistics

    /// Statistics computed off the main actor come back onto it.
    ///
    /// The hook's isolation is already the compiler's problem; what this pins is the runtime
    /// half — that the detached task actually delivers, on the main thread, carrying the text
    /// the coordinator read out of the view rather than an empty string.
    @Test func statisticsAreDeliveredOnTheMainActor() async throws {
        let text = "Two lines here\nand a second"
        coordinator.plainTextByNoteId[0] = text

        await confirmation("the coordinator reports statistics") { reported in
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                // Installed before `setup`, so the delivery cannot land before anyone is
                // listening — which is what makes waiting on it safe instead of racy.
                coordinator.onStats = { _ in
                    reported()
                    continuation.resume()
                }
                coordinator.setup(container: container, notes: notes, selectedIndex: 0)
            }
        }

        let reportedStats = try #require(coordinator.reportedStats.first)
        #expect(coordinator.reportedStats.count == 1)
        #expect(reportedStats.arrivedOnMainThread)
        #expect(reportedStats.stats == TextStats(text: text))
    }

    /// Counts computed for a note the user has already left are dropped rather than shown.
    ///
    /// Each count runs on its own detached task with nothing ordering it against the others, so
    /// two quick note switches can deliver the first note's numbers last — leaving the statistics
    /// bar describing a note that is no longer on screen until the next keystroke corrects it.
    ///
    /// The switches happen back to back on the main actor, so both counts are in flight before
    /// either can land; whichever order they finish in, only note 1's may be reported.
    ///
    /// Waiting for the showing note's delivery rather than draining a task of the same priority
    /// is what stops this passing for the wrong reason: `allSatisfy` on the deliveries that have
    /// landed so far is vacuously true while none of them have, which a drain does not rule out.
    @Test(.bug(id: 50))
    func statisticsForANoteTheUserHasLeftAreDropped() async throws {
        let leftBehind = "First note"
        let showing = "The second note, which is the one on screen"
        coordinator.plainTextByNoteId[0] = leftBehind
        coordinator.plainTextByNoteId[1] = showing

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            // Installed before either count is requested, so the delivery cannot land before
            // anyone is listening.
            coordinator.onStats = { stats in
                if stats == TextStats(text: showing) { continuation.resume() }
            }
            coordinator.setup(container: container, notes: notes, selectedIndex: 0)
            coordinator.update(notes: notes, selectedIndex: 1)
        }

        // The showing note's count has landed, so the note-0 task has had at least that long to
        // finish; this gives its delivery a further turn to arrive before the count is read.
        await Task.detached(priority: .utility) {}.value

        #expect(
            coordinator.reportedStats.map(\.stats) == [TextStats(text: showing)],
            "The bar must never be handed the statistics of the note that was just left")
    }

    private static func isPinned(
        _ view: PlatformView,
        to container: PlatformView,
        on attribute: NSLayoutConstraint.Attribute
    ) -> Bool {
        container.constraints.contains { constraint in
            constraint.isActive
                && constraint.relation == .equal
                && constraint.constant == 0
                && constraint.firstItem === view
                && constraint.firstAttribute == attribute
                && constraint.secondItem === container
                && constraint.secondAttribute == attribute
        }
    }
}
