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

        init(statistics: EditorStatistics) {
            self.statistics = statistics
            super.init()
        }

        override func makeEditorView(for note: NoteItem) -> NSView {
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
            guard let textView = textView(in: editorView) else { return }

            textView.undoManager?.disableUndoRegistration()
            textView.textStorage?.replaceCharacters(
                in: NSRange(location: 0, length: textView.textStorage?.length ?? 0), with: text)
            textView.undoManager?.enableUndoRegistration()
            textView.undoManager?.removeAllActions()

            textView.restyle()
        }

        /// Applies the note's mode and the app-wide zoom. Repaints only — the text is not read,
        /// not rewritten, and the saver is not told anything, because nothing changed.
        override func configure(_ editorView: NSView, appearance: MarkdownStyling.Appearance) {
            guard let textView = textView(in: editorView) else { return }

            textView.styling = appearance
            textView.restyle()
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
                let edit = ListContinuation.returnEdit(
                    in: textView.string as NSString, selectedRange: affectedCharRange)
            else { return true }

            textView.apply(edit)
            return false
        }

        /// Adds "Clear Note" to the editor's context menu — the same action as ⌘⌫, for when
        /// the shortcut is not what comes to mind. This app has no main menu to put it in.
        func textView(
            _ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int
        ) -> NSMenu? {
            menu.addItem(.separator())

            let item = NSMenuItem(
                title: "Clear Note", action: #selector(clearNoteFromMenu(_:)),
                keyEquivalent: "\u{8}")
            item.keyEquivalentModifierMask = .command
            item.target = self
            item.representedObject = view
            menu.addItem(item)

            return menu
        }

        @objc private func clearNoteFromMenu(_ sender: NSMenuItem) {
            (sender.representedObject as? NSTextView)?.clearNote()
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? MarkdownTextView else { return }

            // The storage has already repainted itself by now — the text view is its own
            // storage delegate. Only the typing attributes are left to put back.
            textView.resetTypingAttributes()
            textDidChange(text: textView.string)
        }
    }
}

extension NSTextView {
    /// Empties the note, in one undoable step.
    ///
    /// These notes are meant to be thrown away — a lab ends and its credentials go with it —
    /// which is exactly what makes an accidental clear expensive. Routing it through the
    /// change hooks is what puts it on the per-note undo stack, so ⌘Z brings the note back.
    func clearNote() {
        let range = NSRange(location: 0, length: (string as NSString).length)
        guard range.length > 0, shouldChangeText(in: range, replacementString: "") else { return }

        textStorage?.replaceCharacters(in: range, with: "")
        didChangeText()
        undoManager?.setActionName("Clear Note")
    }
}

/// The editor's text view: its own undo stack, and markdown styling painted on from its text.
class MarkdownTextView: NSTextView, NSTextStorageDelegate {
    private let customUndoManager = UndoManager()

    override var undoManager: UndoManager? {
        return customUndoManager
    }

    /// How this view draws. Display only — none of it is ever stored.
    var styling = MarkdownStyling.Appearance(
        plainText: false, fontSize: AppConstants.Layout.defaultFontSize)

    /// The note leaves on the clipboard as its own characters, never as rich text.
    ///
    /// The view is `isRichText` so it can draw derived styling, and AppKit would otherwise write
    /// that painted-on bold to the pasteboard as RTF. ⌘V reads rich flavors first, so it read the
    /// paint back and re-derived delimiters from it: copying `**keys**` and pasting it returned
    /// `****keys****`. The formatting of a note already *is* its characters, so they are the only
    /// honest thing to write — and it makes the round trip exact rather than merely better.
    ///
    /// Filtered from `super`'s list rather than returned as `[.string]`. AppKit answers this with
    /// its own legacy constants, and `writeSelection(to:type:)` recognises only those — handed
    /// the modern `public.utf8-plain-text` spelling of the same flavor it writes nothing at all
    /// and reports failure, which would make ⌘C copy an empty clipboard.
    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] {
        super.writablePasteboardTypes.filter { !Self.richTextTypes.contains($0.rawValue) }
    }

    private static let richTextTypes: Set<String> = [
        NSPasteboard.PasteboardType.rtf.rawValue,
        NSPasteboard.PasteboardType.rtfd.rawValue,
        "NeXT Rich Text Format v1.0 pasteboard type",
        "NeXT RTFD pasteboard type"
    ]

    /// Repaints the whole note, for when every line's appearance changes at once — a mode
    /// switch, a zoom step, or freshly loaded text.
    func restyle() {
        guard let textStorage else { return }

        MarkdownStyling.apply(styling, to: textStorage)
        resetTypingAttributes()
    }

    /// Repaints the lines an edit landed on.
    ///
    /// Half of the fix for #117: whatever colour or alignment a paste brought with it is gone by
    /// the end of this call, because the lines it landed on are set back to base attributes
    /// before the markdown is drawn. Doing it here rather than in `textDidChange` is what keeps
    /// it to the edited lines — this is the one place the edited range is known.
    func textStorage(
        _ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange, changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }

        MarkdownStyling.apply(styling, to: textStorage, over: editedRange)
    }

    /// The other half of #117, and the half no repaint of the storage can cover.
    ///
    /// `typingAttributes` are not part of the text storage: AppKit sets them from whatever was
    /// pasted, and undo restores the characters without restoring them — which is how deleting a
    /// pasted run left its colour on the caret for everything typed next.
    func resetTypingAttributes() {
        typingAttributes = MarkdownStyling.baseAttributes(styling)
    }
}
