import Cocoa

/// The two app-level actions the shortcut interceptor performs rather than reports, behind a
/// protocol so the dispatch decision can be asserted without carrying it out.
///
/// Both are untestable against the real `NSApp`: `terminate` kills the test process, and
/// `performClose` acts on whichever window another suite happened to make key. ⌘Q and ⌘W were
/// the only arms of `handleAppShortcut` with no coverage as a result. Same seam
/// `WindowManager` already uses for activation — see `ActivationCoordinating`.
@MainActor
protocol AppCommanding: AnyObject {
    /// Quits the app.
    func terminate()

    /// Closes the key window, if there is one. Goes through `performClose` rather than
    /// `close`, so `WindowManager`'s `windowShouldClose` still gets to hide instead.
    func closeKeyWindow()
}

/// The real implementation, talking to `NSApp`.
final class SystemAppCommander: AppCommanding {
    /// `nonisolated` so it can stand as a default argument, which is evaluated in the caller's
    /// context rather than the callee's. It stores nothing; only the two calls below are
    /// isolated, and those are the ones that touch AppKit.
    nonisolated init() {}

    func terminate() {
        NSApp.terminate(nil)
    }

    func closeKeyWindow() {
        NSApp.keyWindow?.performClose(nil)
    }
}
