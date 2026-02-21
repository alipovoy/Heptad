import Foundation
import CoreGraphics

enum AppConstants {
    enum UI {
        /// Padding and spacing within the UI
        static let defaultSpacing: CGFloat = 15

        /// Standard default font size
        static let defaultFontSize: CGFloat = 16
    }

    enum Window {
        /// Threshold for detecting window unpin
        static let unpinThreshold: CGFloat = 20
    }

    enum Timing {
        /// Debounce interval used when saving text
        static let debounceSaveNanoseconds: UInt64 = 300_000_000
    }
}
