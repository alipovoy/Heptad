import SwiftUI

extension View {

    /// Marks a control as chrome: part of the frame around the note rather than the note itself.
    ///
    /// Chrome never takes keyboard focus. On macOS, Full Keyboard Access would otherwise walk the
    /// seven colour circles and the toggles beside them, and the text view losing first responder
    /// takes ⌘B, ⌘I and ⌘V with it — `EditorShortcutManager` finds the view to act on through
    /// `firstResponder`. iOS has no equivalent focus ring to escape, so there it is the identity.
    func chromeControl() -> some View {
        #if os(macOS)
            focusable(false)
        #else
            self
        #endif
    }
}
