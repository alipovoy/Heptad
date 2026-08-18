import UIKit

@testable import Heptad

/// A `MarkdownTextView` in the shape the app installs one: an appearance applied before the note
/// is loaded, since `apply` is what decides whether the buffer holds the source or what it draws.
///
/// `MarkdownTextViewCopyTests` and `MarkdownTextViewPasteTests` are the two halves of one round
/// trip and have to meet the same view, or a copy and the paste it feeds could be measured against
/// different buffers.
///
/// `MarkdownTextViewSelectionTests` deliberately does not use this: it drives `load` on a view that
/// has never been given an appearance, which is the state its clamp tests are about.
@MainActor
func makeTextView(_ markdown: String = "", plainText: Bool = false) -> MarkdownTextView {
    let view = MarkdownTextView()
    view.apply(MarkdownStyling.Appearance(plainText: plainText, fontSize: 16))
    view.load(markdown: markdown)
    return view
}
