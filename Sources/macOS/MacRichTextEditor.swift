import SwiftUI
import AppKit

struct MacRichTextEditor: NSViewRepresentable {
    var note: NoteItem
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        
        textView.delegate = context.coordinator
        textView.allowsUndo = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsImageEditing = false
        textView.font = .systemFont(ofSize: 16) // Good readable default
        
        textView.usesInspectorBar = false
        textView.allowsDocumentBackgroundColorChange = false
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        
        // Apply text padding
        textView.textContainerInset = NSSize(width: 8, height: 8)
        
        if !note.rtfData.isEmpty,
           let attrString = NSAttributedString(rtf: note.rtfData, documentAttributes: nil) {
            textView.textStorage?.setAttributedString(attrString)
        }
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        // Handled entirely by recreating view via .id(note.id) in ContentView
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MacRichTextEditor
        
        init(_ parent: MacRichTextEditor) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            
            let range = NSRange(location: 0, length: textView.textStorage?.length ?? 0)
            if let rtfData = try? textView.textStorage?.data(
                from: range,
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            ) {
                parent.note.rtfData = rtfData
            }
        }
    }
}
