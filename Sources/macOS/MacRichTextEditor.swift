import AppKit
import SwiftUI

struct MacRichTextEditor: NSViewRepresentable {
    var notes: [NoteItem]
    @Binding var selectedNoteIndex: Int

    /// Where the coordinator reports its counts. A reference, so the coordinator keeps writing
    /// to the live one no matter which struct instance SwiftUI is driving at the time.
    let statistics: EditorStatistics

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        context.coordinator.setup(container: container, notes: notes, selectedIndex: selectedNoteIndex)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(notes: notes, selectedIndex: selectedNoteIndex)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(statistics: statistics)
    }

    class Coordinator: NoteEditorCoordinator, NSTextViewDelegate {
        private let statistics: EditorStatistics

        /// Forwards the base class's two seams, so a test can hand this a scratch defaults suite
        /// and a private notification centre.
        init(
            statistics: EditorStatistics,
            defaults: UserDefaults = .standard,
            notificationCenter: NotificationCenter = .default
        ) {
            self.statistics = statistics
            super.init(defaults: defaults, notificationCenter: notificationCenter)
        }

        override func makeEditorView() -> NSView {
            let scrollView = MarkdownTextView.scrollableTextView()
            scrollView.borderType = .noBorder
            scrollView.drawsBackground = false

            // Not `if let`: a failed cast would silently skip every line below — the whole
            // editor configuration *and* the content load — and the note would just come up
            // blank, with nothing logged anywhere to say why. `scrollableTextView()` is
            // documented to vend this class, so a miss is a broken invariant, not a state to
            // degrade into.
            guard let textView = scrollView.documentView as? MarkdownTextView else {
                preconditionFailure("scrollableTextView() must vend a MarkdownTextView")
            }

            textView.delegate = self

            // The view paints its own styling from its own text, on the one hook that knows
            // which characters changed. See `MarkdownTextView.textStorage(_:didProcessEditing:…)`.
            textView.textStorage?.delegate = textView

            textView.allowsUndo = true
            textView.importsGraphics = false
            textView.allowsImageEditing = false

            // Rich in what it can *draw*, never in what it stores: the styling is recomputed
            // from the text after every change and only `string` is saved. A plain-text view
            // would refuse the derived attributes outright. See `MarkdownStyling`.
            textView.isRichText = true

            textView.usesInspectorBar = false
            textView.allowsDocumentBackgroundColorChange = false
            textView.backgroundColor = .clear
            textView.drawsBackground = false

            // Apply text padding
            textView.textContainerInset = NSSize(width: 8, height: 8)

            return scrollView
        }

        override func load(_ text: String, into editorView: NSView) {
            textView(in: editorView)?.load(markdown: text)
        }

        /// Applies the note's mode and the app-wide zoom.
        ///
        /// A zoom step only repaints. A *mode* step rewrites the buffer, because the two modes
        /// hold different things: formatted mode holds rich text with no delimiters in it, plain
        /// mode holds the source. See `MarkdownTextView.apply(_:)`.
        override func configure(_ editorView: NSView, appearance: MarkdownStyling.Appearance) {
            textView(in: editorView)?.apply(appearance)
        }

        override func resignFocus(from editorView: NSView) {
            guard let textView = textView(in: editorView),
                let window = editorView.window,
                window.firstResponder == textView
            else { return }

            window.makeFirstResponder(container)
        }

        override func focus(_ editorView: NSView) {
            if let textView = textView(in: editorView) {
                editorView.window?.makeFirstResponder(textView)
            }
        }

        override func plainText(of editorView: NSView) -> String {
            textView(in: editorView)?.string ?? ""
        }

        override func markdown(of editorView: NSView) -> String {
            textView(in: editorView)?.markdown ?? ""
        }

        override func statsDidChange(_ stats: TextStats) {
            statistics.stats = stats
        }

        private func textView(in editorView: NSView) -> MarkdownTextView? {
            (editorView as? NSScrollView)?.documentView as? MarkdownTextView
        }

        /// Continues or ends a list when Return is pressed on one, by making the edit here and
        /// declining the newline that would otherwise be inserted.
        ///
        /// Re-entrant by design: `apply` calls `shouldChangeText(in:replacementString:)`, which
        /// asks this method again — with the marker text, never a bare "\n", so it passes.
        func textView(
            _ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard replacementString == "\n",
                let markdownView = textView as? MarkdownTextView,
                let edit = ListContinuation.returnEdit(
                    in: textView.string as NSString, selectedRange: affectedCharRange)
            else { return true }

            markdownView.applyMarkup(edit)
            return false
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? MarkdownTextView else { return }

            // The storage has already been normalized by now — the text view is its own storage
            // delegate. Only the typing attributes are left, which no storage pass can reach.
            textView.normalizeTypingAttributes()
            noteDidChange()
        }
    }
}

/// The editor's text view: its own undo stack, and a buffer whose shape is its note's mode.
///
/// Formatted mode holds rich text — bold is a bold font, and there is no markdown in the buffer
/// at all. Plain mode holds the source, every delimiter visible. The note is markdown either way;
/// what changes is only what this view is holding, and `apply(_:)` is where it converts.
class MarkdownTextView: NSTextView, NSTextStorageDelegate {
    private let customUndoManager = UndoManager()

    override var undoManager: UndoManager? {
        return customUndoManager
    }

    /// How this view draws, and which of the two shapes its buffer is in. Display only — none of
    /// it is ever stored.
    ///
    /// Held as `nil` until something configures it, which is what makes the first `configure` do
    /// anything: `apply` returns early on an appearance it already has, so any stand-in starting
    /// value would swallow a first call that happened to match it — a formatted note at the default
    /// zoom is exactly that shape.
    private var configuredStyling: MarkdownStyling.Appearance?

    /// What the view draws as now: what it was last configured with, or what a bare text view is
    /// before anything has.
    var styling: MarkdownStyling.Appearance { configuredStyling ?? Self.unconfigured }

    private static let unconfigured = MarkdownStyling.Appearance(
        plainText: false, fontSize: AppConstants.Layout.defaultFontSize)

    /// What ⌘C, ⌘X and a drag out of the note leave on the clipboard.
    ///
    /// Three flavors in formatted mode, so the destination picks rather than this app guessing:
    /// RTF for a document that draws formatting, the note's markdown for anything that takes
    /// text, and `.heptadMarkdown` for this app itself — see `markdownForPaste`, which reads it
    /// verbatim so a copy from one note into another converts nothing at all.
    ///
    /// AppKit's own RTF is what is filtered out, and both are needed: it writes the *drawn*
    /// buffer, note tint and editor zoom included, where `RichTextExport` writes the vocabulary
    /// and nothing else. Before either existed, ⌘V read that painted-on bold back and re-derived
    /// delimiters from it — copying `**keys**` and pasting it returned `****keys****`.
    ///
    /// A plain-text note offers neither: that mode has no formatting to carry, so the rich flavor
    /// would be the same characters at more expense.
    ///
    /// The plain flavors are filtered from `super`'s list rather than spelled `[.string]`. AppKit
    /// answers this with its own legacy constants, and `super.writeSelection(to:type:)`
    /// recognises only those — handed the modern `public.utf8-plain-text` spelling of the same
    /// flavor it writes nothing at all and reports failure, which would make ⌘C copy an empty
    /// clipboard.
    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] {
        let plain = super.writablePasteboardTypes.filter { !Self.richTextTypes.contains($0.rawValue) }
        guard styling.isStyled else { return plain }

        // Richest first, which is the order a receiver that asks for a list expects.
        return [.rtf, .heptadMarkdown] + plain
    }

    private static let richTextTypes: Set<String> = [
        NSPasteboard.PasteboardType.rtf.rawValue,
        NSPasteboard.PasteboardType.rtfd.rawValue,
        "NeXT Rich Text Format v1.0 pasteboard type",
        "NeXT RTFD pasteboard type"
    ]

    /// The note as it would be stored: markdown, whichever mode this view is in.
    var markdown: String {
        guard let textStorage else { return "" }
        return styling.isStyled ? MarkdownWriting.markdown(from: textStorage) : string
    }

    /// The selection as markdown — what ⌘C writes, and what ⌘⇧C renders to RTF.
    ///
    /// One spelling of "the selected text", so the two commands cannot come to disagree about
    /// where a run ends.
    var selectedMarkdown: String {
        guard let textStorage else { return "" }
        guard styling.isStyled else {
            return (string as NSString).substring(with: selectedRange())
        }

        return MarkdownWriting.markdown(
            from: textStorage.attributedSubstring(from: selectedRange()))
    }

    /// Puts a note's markdown into the view, in the shape its mode calls for.
    ///
    /// Undo registration is off for this and the stack is emptied after it: what is being
    /// replaced is the whole buffer, and an undo step recorded against the note that was in it
    /// describes ranges in text that is gone.
    func load(markdown: String) {
        guard let textStorage else { return }

        let caret = selectedRange()
        undoManager?.disableUndoRegistration()
        textStorage.setAttributedString(
            RichTextRendering.attributed(from: markdown, appearance: styling))
        undoManager?.enableUndoRegistration()
        undoManager?.removeAllActions()

        setSelectedRange(
            NSRange(location: min(caret.location, textStorage.length), length: 0))
        typingAttributes = MarkdownStyling.baseAttributes(styling)
    }

    /// Applies an edit whose replacement is markup this app wrote — a list marker, a checkbox —
    /// in the note's own body face rather than in whatever run it lands in.
    ///
    /// `caretFollowsMarkup` defaults to true for the list continuation, which is where the caret
    /// ends up. See `TextEdit` for what it costs to get it wrong.
    func applyMarkup(_ edit: TextEdit, caretFollowsMarkup: Bool = true) {
        apply(
            edit, attributes: MarkdownStyling.baseAttributes(styling),
            caretFollowsMarkup: caretFollowsMarkup)
    }

    /// Applies a mode and a zoom level.
    ///
    /// A zoom step normalizes, which rebuilds every run's font at the new size with its traits
    /// intact. A *mode* step converts the buffer instead: the two modes hold different text, so
    /// the note is written out of the shape it is in and read back into the other one. That
    /// conversion is the only styling work this editor does on anything but a load — which is the
    /// point of #124's redesign. Typing is no longer a parse.
    func apply(_ appearance: MarkdownStyling.Appearance) {
        guard let textStorage else { return }
        guard appearance != configuredStyling else { return }

        // Read before the new appearance is recorded, and only for a mode step: writing the buffer
        // out renders every line through the spelling ladder, which is more work than the repaint
        // a zoom step asks for.
        let source = appearance.plainText != styling.plainText ? markdown : nil
        configuredStyling = appearance

        if let source {
            load(markdown: source)
        } else {
            MarkdownStyling.normalize(styling, in: textStorage)
            typingAttributes = MarkdownStyling.normalized(typingAttributes, in: styling)
        }
    }

    /// Takes an edit back to what this app can express.
    ///
    /// The fix for #117 in its new shape. A paste can still arrive carrying colour, alignment and
    /// a font of its own — through a drag, or through `readSelection` — and this is what strips
    /// the lot while keeping the bold. Doing it here rather than in `textDidChange` is what keeps
    /// it to the range the edit landed on: this is the one place that range is known.
    func textStorage(
        _ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange, changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }

        MarkdownStyling.normalize(styling, in: textStorage, over: editedRange)
    }

    /// The other half of #117, and the half no pass over the storage can cover.
    ///
    /// `typingAttributes` are not part of the text storage: AppKit sets them from whatever was
    /// pasted, and undo restores the characters without restoring them — which is how deleting a
    /// pasted run left its colour on the caret for everything typed next. Normalized rather than
    /// reset, because in this mode the caret legitimately carries the bold it is sitting in.
    func normalizeTypingAttributes() {
        typingAttributes = MarkdownStyling.normalized(typingAttributes, in: styling)
    }

    /// Fills in one flavor of what `writablePasteboardTypes` offered.
    ///
    /// The two text flavors are the note's own markdown, not the characters on screen: the buffer
    /// holds no delimiters any more, so the characters alone would put a note's formatting on the
    /// clipboard and lose it.
    override func writeSelection(
        to pboard: NSPasteboard, type: NSPasteboard.PasteboardType
    ) -> Bool {
        guard styling.isStyled else {
            return super.writeSelection(to: pboard, type: type)
        }

        guard type == .rtf else {
            return pboard.setString(selectedMarkdown, forType: type)
        }

        // A selection with nothing in it has no RTF to write. Reported as a failure rather than
        // written empty, so the flavor is simply absent instead of holding an empty document.
        guard let rtf = RichTextExport.rtf(from: selectedMarkdown) else { return false }
        return pboard.setData(rtf, forType: type)
    }
}
