import Foundation
import CoreGraphics

enum AppConstants {
    enum UI {
        /// Padding and spacing within the UI
        static let defaultSpacing: CGFloat = 12

        /// Standard default font size
        static let defaultFontSize: CGFloat = 16

        enum ColorCircle {
            /// Circle diameter = defaultFontSize * sizeMultiplier
            static let sizeMultiplier: CGFloat = 1.2
            static let strokeLineWidth: CGFloat = 3
            /// Font size for selected note number = circle size * selectedNumberFontScale
            static let selectedNumberFontScale: CGFloat = 0.8
        }
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
