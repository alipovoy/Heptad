import Observation

/// The one piece of window state the views are allowed to see.
///
/// Deliberately not `@AppStorage`-backed, and deliberately not persisted anywhere: detaching is
/// a state the window is *in*, not a preference. It lasts until the window leaves the screen and
/// no longer — see `WindowManager.hide(_:)`, which is what puts it back.
///
/// `WindowManager` is the only writer. `TextStatisticsBar` reads it out of the environment to
/// draw the pin toggle, which is the whole reason it is a type rather than a private field:
/// observation is what repaints that button when ⌘P or a drag flips the state under it.
@MainActor
@Observable
final class WindowState {
    /// True while the window is detached — an ordinary window the user has parked somewhere,
    /// rather than the menubar panel. See `WindowManager` for the two modes in full.
    var isPinned = false
}
