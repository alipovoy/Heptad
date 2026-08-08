#if canImport(UIKit)
    import UIKit

    typealias PlatformColor = UIColor
    typealias PlatformFont = UIFont
    typealias PlatformView = UIView
#else
    import AppKit

    typealias PlatformColor = NSColor
    typealias PlatformFont = NSFont
    typealias PlatformView = NSView
#endif
