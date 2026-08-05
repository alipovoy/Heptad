import Foundation

#if canImport(UIKit)
    import UIKit

    typealias PlatformFont = UIFont
#else
    import AppKit

    typealias PlatformFont = NSFont
#endif

/// What a note's plain-text mode means to the text it holds.
///
/// The store stays RTF in both modes — nothing about persistence changes. Plain mode is the
/// editor refusing to add attributes, plus this one set of them painted over everything the
/// note already had: temp credentials and API keys are structured text, and a proportional
/// font makes them hard to read.
enum PlainTextMode {
    /// The attributes a note's whole text is flattened to when its mode changes. Switching
    /// modes rewrites how the text looks, never what it says.
    static func attributes(plainText: Bool) -> [NSAttributedString.Key: Any] {
        [
            .font: PlatformFont.editorBody(plainText: plainText),
            .foregroundColor: PlatformColor.adaptiveEditorText
        ]
    }
}

extension PlatformFont {
    static func editorBody(plainText: Bool) -> PlatformFont {
        let size = AppConstants.Layout.defaultFontSize
        return plainText
            ? .monospacedSystemFont(ofSize: size, weight: .regular)
            : .systemFont(ofSize: size)
    }
}
