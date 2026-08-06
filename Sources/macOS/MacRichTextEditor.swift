import AppKit
import SwiftUI

struct MacRichTextEditor: NSViewRepresentable {
    var notes: [NoteItem]
    @Binding var selectedNoteIndex: Int
    @Binding var textStats: TextStats

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        context.coordinator.setup(container: container, notes: notes, selectedIndex: selectedNoteIndex)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // The coordinator outlives every struct instance that drives it, so without this it
        // keeps the one handed to `makeCoordinator` — and any `parent.` read sees launch-time
        // values forever. Today only the `textStats` binding is read through it, and a Binding
        // is a pair of closures rather than a snapshot, so the stale parent still writes to the
        // live state; that is incidental, and this keeps it from mattering.
        context.coordinator.parent = self
        context.coordinator.update(notes: notes, selectedIndex: selectedNoteIndex)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NoteEditorCoordinator, NSTextViewDelegate {
        var parent: MacRichTextEditor

        init(_ parent: MacRichTextEditor) {
            self.parent = parent
        }

        override func makeEditorView(for note: NoteItem) -> NSView {
            let scrollView = IsolatedUndoTextView.scrollableTextView()
            scrollView.borderType = .noBorder
            scrollView.drawsBackground = false

            // Not `if let`: a failed cast would silently skip every line below — the whole
            // editor configuration *and* the content load — and the note would just come up
            // blank, with nothing logged anywhere to say why. `scrollableTextView()` is
            // documented to vend this class, so a miss is a broken invariant, not a state to
            // degrade into.
            guard let textView = scrollView.documentView as? IsolatedUndoTextView else {
                preconditionFailure("scrollableTextView() must vend an IsolatedUndoTextView")
            }

            textView.delegate = self
            textView.allowsUndo = true
            // Plain mode is `isRichText = false`, which is also what makes ⌘V paste unstyled.
            textView.isRichText = !note.isPlainText
            textView.importsGraphics = false
            textView.allowsImageEditing = false
            textView.font = .editorBody(plainText: note.isPlainText)

            textView.usesInspectorBar = false
            textView.allowsDocumentBackgroundColorChange = false
            textView.backgroundColor = .clear
            textView.drawsBackground = false

            // Apply text padding
            textView.textContainerInset = NSSize(width: 8, height: 8)

            if let attrString = note.attributedContent {
                textView.undoManager?.disableUndoRegistration()
                textView.textStorage?.setAttributedString(attrString)
                textView.undoManager?.enableUndoRegistration()
                textView.undoManager?.removeAllActions()
            }

            return scrollView
        }

        /// Switches the visible text view between rich and plain, flattening what is already
        /// there. `isRichText` is the applied state, so this is a no-op until the note's mode
        /// actually changes.
        override func configure(_ editorView: NSView, for note: NoteItem) {
            guard let textView = textView(in: editorView),
                textView.isRichText == note.isPlainText
            else { return }

            textView.isRichText = !note.isPlainText

            let attributes = PlainTextMode.attributes(plainText: note.isPlainText)
            textView.typingAttributes = attributes

            // Through the change hooks, so the flattening is one undo step and reaches the
            // saver — the note keeps its text and loses only how it looked.
            guard let textStorage = textView.textStorage, textStorage.length > 0 else { return }
            let range = NSRange(location: 0, length: textStorage.length)
            guard textView.shouldChangeText(in: range, replacementString: nil) else { return }

            textStorage.setAttributes(attributes, range: range)
            textView.didChangeText()
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
            parent.textStats = stats
        }

        private func textView(in editorView: NSView) -> NSTextView? {
            (editorView as? NSScrollView)?.documentView as? NSTextView
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
            guard let textView = notification.object as? NSTextView,
                let textStorage = textView.textStorage
            else { return }

            // The storage itself, not a copy of it: the saver reads it once per debounce
            // window rather than once per keystroke. See `NoteContentSaver.save`.
            textDidChange(attributedString: textStorage, plainText: textView.string)
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

class IsolatedUndoTextView: NSTextView {
    private let customUndoManager = UndoManager()

    override var undoManager: UndoManager? {
        return customUndoManager
    }
}
