import SwiftUI
import UIKit

struct IOSRichTextEditor: UIViewRepresentable {
    var note: NoteItem
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        
        textView.delegate = context.coordinator
        textView.allowsEditingTextAttributes = true
        textView.font = .systemFont(ofSize: 18)
        textView.backgroundColor = .clear
        
        // Apply text padding
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        
        if !note.rtfData.isEmpty,
           let attrString = try? NSAttributedString(
                data: note.rtfData,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
           ) {
            textView.attributedText = attrString
        }
        
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        // Handled entirely by recreating view via .id(note.id) in ContentView
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: IOSRichTextEditor
        
        init(_ parent: IOSRichTextEditor) {
            self.parent = parent
        }
        
        func textViewDidChange(_ textView: UITextView) {
            let range = NSRange(location: 0, length: textView.attributedText.length)
            if let rtfData = try? textView.attributedText.data(
                from: range,
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            ) {
                parent.note.rtfData = rtfData
            }
        }
    }
}
