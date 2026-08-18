import Cocoa

/// The slice of system-wide activation state the window manager touches, behind a protocol so
/// the hand-off can be tested without switching real applications around.
protocol ActivationCoordinating: AnyObject {
    /// True while Heptad itself is the active application.
    var isCurrentAppActive: Bool { get }

    /// The app that currently owns activation, whichever it is.
    var frontmostApplication: NSRunningApplication? { get }

    /// Makes Heptad the active application.
    func activateCurrentApp()

    /// Hands activation to another app, restoring its key window and first responder.
    func activate(_ app: NSRunningApplication)

    /// Gives up active status without naming a successor — the fallback when there is no
    /// remembered app to hand back to.
    func deactivateCurrentApp()
}

/// The real implementation, talking to `NSApp` and `NSWorkspace`.
final class SystemActivationCoordinator: ActivationCoordinating {
    var isCurrentAppActive: Bool { NSApp.isActive }

    var frontmostApplication: NSRunningApplication? { NSWorkspace.shared.frontmostApplication }

    /// `activate()` rather than `activate(ignoringOtherApps: true)`, which is deprecated on
    /// macOS 14 — where activation became cooperative and the "ignoring" half is not honoured
    /// anyway. What actually grants it is the user event this is a response to: a click on the
    /// status item, or the global hotkey.
    func activateCurrentApp() {
        NSApp.activate()
    }

    func activate(_ app: NSRunningApplication) {
        app.activate()
    }

    func deactivateCurrentApp() {
        NSApp.deactivate()
    }
}
