import Foundation
import Testing

#if canImport(UIKit)
    import UIKit
#else
    import AppKit
#endif

@testable import Heptad

/// The seam the coordinator already exposes: a subclass whose platform hooks hand back bare
/// views and record what the shared logic did with them. No AppKit or UIKit text view is
/// involved, so the same suite runs on both targets and nothing in `Sources` had to change.
@MainActor
private final class SpyEditorCoordinator: NoteEditorCoordinator {

    /// Where `resignFocus` found the outgoing view when it was called.
    ///
    /// The superview is captured at call time rather than read afterwards because the
    /// ordering is the point: the coordinator resigns first responder *while the view is
    /// still installed*, and reading `superview` after the fact can no longer tell the two
    /// orderings apart.
    struct ResignedView {
        let view: PlatformView
        let superviewAtCall: PlatformView?
    }

    /// Note ids passed to `makeEditorView`, in call order. The length is the assertion that
    /// matters: view creation and saver creation sit behind the same `editorViews[id] == nil`
    /// check, so a second entry here would mean a second saver for that note too.
    /// A statistics delivery, plus where it landed.
    ///
    /// `statsDidChange` is declared on a `@MainActor` class, so the compiler already forces
    /// the hop; the flag is the runtime witness that it actually happened rather than an
    /// assertion the isolation checker erased.
    struct ReportedStats {
        let stats: TextStats
        let arrivedOnMainThread: Bool
    }

    private(set) var madeViewNoteIds: [Int] = []
    private(set) var resignedViews: [ResignedView] = []
    private(set) var reportedStats: [ReportedStats] = []

    /// What each note's view reports as its text; the real subclasses read this off a text view.
    var plainTextByNoteId: [Int: String] = [:]

    /// Fires on every `statsDidChange`, so a test can resume once the detached work lands
    /// instead of guessing how long it takes.
    var onStats: ((TextStats) -> Void)?

    private var noteIdsByView: [ObjectIdentifier: Int] = [:]

    override func makeEditorView(for note: NoteItem) -> PlatformView {
        madeViewNoteIds.append(note.id)
        let view = PlatformView()
        noteIdsByView[ObjectIdentifier(view)] = note.id
        return view
    }

    override func resignFocus(from editorView: PlatformView) {
        resignedViews.append(ResignedView(view: editorView, superviewAtCall: editorView.superview))
    }

    override func plainText(of editorView: PlatformView) -> String {
        guard let noteId = noteIdsByView[ObjectIdentifier(editorView)] else { return "" }
        return plainTextByNoteId[noteId] ?? ""
    }

    override func statsDidChange(_ stats: TextStats) {
        reportedStats.append(ReportedStats(stats: stats, arrivedOnMainThread: Thread.isMainThread))
        onStats?(stats)
    }
}

@MainActor
struct NoteEditorCoordinatorTests {

    private let coordinator = SpyEditorCoordinator()
    private let container = PlatformView()
    private let notes = [NoteItem(id: 0), NoteItem(id: 1)]

    // MARK: - Selection

    /// A selection the notes array cannot answer leaves the coordinator exactly as it was.
    ///
    /// Both halves matter: nothing is built for a bad index on a cold coordinator, and — the
    /// case that would actually be visible to a user — a bad index arriving while a note is on
    /// screen must not tear that note down. The guard returns before the removal, so the
    /// showing view keeps its focus and its place in the container.
    @Test(arguments: [-1, 1, 42])
    func outOfRangeSelectionIsIgnored(selectedIndex: Int) {
        let oneNote = [notes[0]]
        coordinator.setup(container: container, notes: oneNote, selectedIndex: selectedIndex)

        #expect(coordinator.currentNoteId == nil)
        #expect(coordinator.madeViewNoteIds.isEmpty)
        #expect(container.subviews.isEmpty)

        coordinator.update(notes: oneNote, selectedIndex: 0)
        coordinator.update(notes: oneNote, selectedIndex: selectedIndex)

        #expect(coordinator.currentNoteId == 0)
        #expect(coordinator.madeViewNoteIds == [0])
        #expect(coordinator.resignedViews.isEmpty)
        #expect(container.subviews.count == 1)
    }

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
        coordinator.textDidChange(attributedString: NSAttributedString(string: typed), plainText: typed)

        // Poll to a deadline rather than sleeping past the 300 ms debounce: the flat sleep
        // races process warm-up and CPU contention for whatever margin was hardcoded. Inlined
        // rather than shared because the existing `waitUntil` is an `XCTestCase` extension,
        // which a Swift Testing suite cannot reach.
        let deadline = ContinuousClock.now + .seconds(5)
        while notes[1].rtfData.isEmpty {
            try #require(ContinuousClock.now < deadline, "timed out waiting for the debounced save")
            try await Task.sleep(for: .milliseconds(10))
        }

        // Reaching here already proves note 1 was written. Note 0 stays empty for the strong
        // reason, not a timing one: its saver was never handed anything to write, and had the
        // text gone there instead this wait would have expired rather than fallen through.
        #expect(notes[0].rtfData.isEmpty)
    }

    /// Text arriving before any `setup` is dropped instead of crashing.
    ///
    /// Not hypothetical on macOS: `NSTextView` delegate callbacks can fire while the editor is
    /// being torn down and rebuilt, when there is no current note and no saver to route to.
    @Test func textDidChangeBeforeSetupIsIgnored() async {
        let typed = "Typed into nothing"
        coordinator.textDidChange(attributedString: NSAttributedString(string: typed), plainText: typed)

        #expect(coordinator.currentNoteId == nil)
        #expect(notes[0].rtfData.isEmpty)
        #expect(notes[1].rtfData.isEmpty)

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
