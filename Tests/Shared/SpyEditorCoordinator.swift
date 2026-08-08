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
final class SpyEditorCoordinator: NoteEditorCoordinator {

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

    /// Note ids passed to `configure`, in call order.
    private(set) var configuredNoteIds: [Int] = []

    /// The appearances `configure` was handed, in call order.
    private(set) var configuredAppearances: [MarkdownStyling.Appearance] = []

    /// What the coordinator had done by the time each hook ran, so the ordering
    /// `makeCachedEditorView` keeps can be asserted rather than assumed.
    private(set) var stepsInOrder: [String] = []

    /// What each note's view reports as its text; the real subclasses read this off a text view.
    var plainTextByNoteId: [Int: String] = [:]

    /// Fires on every `statsDidChange`, so a test can resume once the detached work lands
    /// instead of guessing how long it takes.
    var onStats: ((TextStats) -> Void)?

    private var noteIdsByView: [ObjectIdentifier: Int] = [:]

    /// Forwards the coordinator's own injection seams. Without them `appearance(forNoteId:)`
    /// reads `UserDefaults.standard` and the zoom repaint listens on `NotificationCenter.default`,
    /// so a test that stepped the zoom in a scratch suite would be watching a notification the
    /// coordinator never hears — the "half an injection seam" its initializer warns about.
    override init(
        defaults: UserDefaults = .standard, notificationCenter: NotificationCenter = .default
    ) {
        super.init(defaults: defaults, notificationCenter: notificationCenter)
    }

    override func makeEditorView(for note: NoteItem) -> PlatformView {
        madeViewNoteIds.append(note.id)
        stepsInOrder.append("make")
        let view = PlatformView()
        noteIdsByView[ObjectIdentifier(view)] = note.id
        return view
    }

    override func configure(_ editorView: PlatformView, appearance: MarkdownStyling.Appearance) {
        // The hook is handed an appearance rather than a note, so the id comes from the view it
        // was built for — the same map `plainText(of:)` reads.
        configuredNoteIds.append(noteIdsByView[ObjectIdentifier(editorView)] ?? -1)
        configuredAppearances.append(appearance)
        stepsInOrder.append("configure(showing: \(currentNoteId.map(String.init) ?? "nil"))")
    }

    override func load(_ text: String, into editorView: PlatformView) {
        stepsInOrder.append("load")
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
