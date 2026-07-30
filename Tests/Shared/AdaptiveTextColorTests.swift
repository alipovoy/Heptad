import XCTest

#if canImport(UIKit)
    import UIKit
#else
    import AppKit
#endif

@testable import Heptad

final class AdaptiveTextColorTests: XCTestCase {
    private let font = PlatformFont.systemFont(ofSize: 14)

    // MARK: - Filling in the color

    func testFillsInColorForColorlessText() throws {
        let string = NSAttributedString(string: "hello", attributes: [.font: font])

        let filled = string.fillingInAdaptiveTextColor()

        let color = try XCTUnwrap(filled.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? PlatformColor)
        XCTAssertEqual(color, .adaptiveEditorText)
    }

    func testKeepsExplicitColor() {
        let string = NSAttributedString(string: "hello", attributes: [.foregroundColor: PlatformColor.red])

        let filled = string.fillingInAdaptiveTextColor()

        XCTAssertEqual(filled.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? PlatformColor, .red)
    }

    func testFillsInOnlyTheColorlessRuns() throws {
        let string = NSMutableAttributedString(string: "red", attributes: [.foregroundColor: PlatformColor.red])
        string.append(NSAttributedString(string: "plain", attributes: [.font: font]))

        let filled = string.fillingInAdaptiveTextColor()

        XCTAssertEqual(filled.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? PlatformColor, .red)
        let plain = try XCTUnwrap(filled.attribute(.foregroundColor, at: 3, effectiveRange: nil) as? PlatformColor)
        XCTAssertEqual(plain, .adaptiveEditorText)
    }

    func testEmptyStringIsUnchanged() {
        XCTAssertEqual(NSAttributedString(string: "").fillingInAdaptiveTextColor(), NSAttributedString(string: ""))
    }

    /// The point of the whole exercise: the filled-in color has to follow the appearance,
    /// otherwise the text is simply black again.
    func testFilledInColorFollowsTheAppearance() throws {
        let filled = NSAttributedString(string: "hello", attributes: [.font: font])
            .fillingInAdaptiveTextColor()
        let color = try XCTUnwrap(filled.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? PlatformColor)

        let light = try components(of: color, inDarkAppearance: false)
        XCTAssertLessThan(max(light.red, light.green, light.blue), 0.1, "black in light appearance")

        let dark = try components(of: color, inDarkAppearance: true)
        XCTAssertGreaterThan(min(dark.red, dark.green, dark.blue), 0.9, "white in dark appearance")
    }

    // MARK: - The stored-note path

    /// Notes are stored without a color whenever their text carried none, which is how RTF
    /// written before this behaviour existed comes back. Loading one must not yield black text.
    func testStoredNoteWithoutAColorLoadsWithTheAdaptiveColor() throws {
        let stored = NSAttributedString(string: "stored note", attributes: [.font: font])
        let data = try XCTUnwrap(NoteItem.rtfData(from: stored))
        let note = NoteItem(id: 0, rtfData: data)

        let loaded = try XCTUnwrap(note.attributedContent)

        XCTAssertEqual(loaded.string, "stored note")
        let color = try XCTUnwrap(loaded.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? PlatformColor)
        XCTAssertEqual(color, .adaptiveEditorText)
    }

    /// A color the editors did write survives the round trip, so reloading doesn't flatten it.
    func testStoredExplicitColorSurvivesLoading() throws {
        let stored = NSAttributedString(string: "red note", attributes: [.foregroundColor: PlatformColor.red])
        let data = try XCTUnwrap(NoteItem.rtfData(from: stored))
        let note = NoteItem(id: 0, rtfData: data)

        let loaded = try XCTUnwrap(note.attributedContent)

        let color = try XCTUnwrap(loaded.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? PlatformColor)
        XCTAssertNotEqual(color, .adaptiveEditorText)

        let dark = try components(of: color, inDarkAppearance: true)
        XCTAssertGreaterThan(dark.red, 0.9, "still red, not repainted")
        XCTAssertLessThan(max(dark.green, dark.blue), 0.1)
    }

    // MARK: - Helpers

    private struct RGB {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
    }

    /// Resolves `color` in the given appearance, which is how these tests tell an adaptive
    /// color from a fixed one.
    private func components(of color: PlatformColor, inDarkAppearance isDark: Bool) throws -> RGB {
        var rgb = RGB()
        #if canImport(UIKit)
            let traits = UITraitCollection(userInterfaceStyle: isDark ? .dark : .light)
            var alpha: CGFloat = 0
            let converted = color.resolvedColor(with: traits)
                .getRed(&rgb.red, green: &rgb.green, blue: &rgb.blue, alpha: &alpha)
            XCTAssertTrue(converted, "expected an RGB-convertible color")
        #else
            let appearance = try XCTUnwrap(NSAppearance(named: isDark ? .darkAqua : .aqua))
            appearance.performAsCurrentDrawingAppearance {
                guard let resolved = color.usingColorSpace(.sRGB) else { return }
                rgb = RGB(red: resolved.redComponent, green: resolved.greenComponent, blue: resolved.blueComponent)
            }
        #endif
        return rgb
    }
}

#if canImport(UIKit)
    private typealias PlatformFont = UIFont
#else
    private typealias PlatformFont = NSFont
#endif
