import Testing

/// Tags for the tests that need something from the machine rather than only from the code.
///
/// Everything else in this project is a pure function of its inputs and runs anywhere. The few
/// tests that are not say so here, so a run can be narrowed to the deterministic core — which is
/// what you want while chasing a regression, and what makes an unexpected failure in a tagged
/// test read as "the environment" rather than "the code".
///
/// Filter with, for example:
/// `xcodebuild test -skip-testing-with-tag windowServer`
extension Tag {
    /// Needs a real window server: puts an `NSWindow` on screen, or depends on key-window status
    /// being granted. These cannot run headless and are the ones that suffer under contention.
    @Tag static var windowServer: Self

    /// Claims a resource that is process-wide or system-wide — a global hotkey registration, for
    /// instance — so it can fail because of what else is running rather than because of a bug.
    @Tag static var systemResource: Self
}
