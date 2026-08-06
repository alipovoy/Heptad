import Foundation
import Testing

#if canImport(UIKit)
    import UIKit
#else
    import AppKit
#endif

@testable import Heptad

/// Serialized because `components(of:inDarkAppearance:)` drives
/// `performAsCurrentDrawingAppearance`, which sets a thread-global appearance — two of these
/// tests running concurrently would resolve colours against each other's appearance.
@Suite(.serialized)
@MainActor
struct AdaptiveTextColorTests {
    private let font = PlatformFont.systemFont(ofSize: 14)

    // MARK: - Filling in the color

    @Test func fillsInOnlyTheColorlessRuns() throws {
        let string = NSMutableAttributedString(string: "red", attributes: [.foregroundColor: PlatformColor.red])
        string.append(NSAttributedString(string: "plain", attributes: [.font: font]))

        let filled = string.fillingInAdaptiveTextColor()

        #expect(filled.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? PlatformColor == .red)
        let plain = try #require(filled.attribute(.foregroundColor, at: 3, effectiveRange: nil) as? PlatformColor)
        #expect(plain == .adaptiveEditorText)
    }

    @Test func emptyStringIsUnchanged() {
        #expect(NSAttributedString(string: "").fillingInAdaptiveTextColor() == NSAttributedString(string: ""))
    }

    // MARK: - The stored-note path

    /// Notes are stored without a color whenever their text carried none, which is how RTF
    /// written before this behaviour existed comes back. Loading one must not yield black text.
    @Test func storedNoteWithoutAColorLoadsWithTheAdaptiveColor() throws {
        let stored = NSAttributedString(string: "stored note", attributes: [.font: font])
        let data = try #require(NoteItem.rtfData(from: stored))
        let note = NoteItem(id: 0, rtfData: data)

        let loaded = try #require(note.attributedContent)

        #expect(loaded.string == "stored note")
        let color = try #require(loaded.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? PlatformColor)
        #expect(color == .adaptiveEditorText)
    }

    /// A color the editors did write survives the round trip, so reloading doesn't flatten it.
    @Test func storedExplicitColorSurvivesLoading() throws {
        let stored = NSAttributedString(string: "red note", attributes: [.foregroundColor: PlatformColor.red])
        let data = try #require(NoteItem.rtfData(from: stored))
        let note = NoteItem(id: 0, rtfData: data)

        let loaded = try #require(note.attributedContent)

        let color = try #require(loaded.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? PlatformColor)
        #expect(color != .adaptiveEditorText)

        let dark = try components(of: color, inDarkAppearance: true)
        #expect(dark.red > 0.9, "still red, not repainted")
        #expect(max(dark.green, dark.blue) < 0.1)
    }

    /// The case every user hits, and the one the other stored-note tests miss. Loading a note
    /// stamps the adaptive color across the whole storage, so from the next save onwards the
    /// RTF carries an *explicit* color — and it has to be the named system color, not the
    /// appearance it happened to be authored in. A regression here bakes the authoring
    /// appearance into the file permanently and stays invisible until someone switches theme.
    @Test(.bug(id: 45))
    func theFilledInColorSurvivesASaveAndReload() throws {
        let filled = NSAttributedString(string: "note", attributes: [.font: font])
            .fillingInAdaptiveTextColor()
        let note = NoteItem(id: 0, rtfData: try #require(NoteItem.rtfData(from: filled)))

        let loaded = try #require(note.attributedContent)
        let color = try #require(loaded.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? PlatformColor)

        let light = try components(of: color, inDarkAppearance: false)
        #expect(max(light.red, light.green, light.blue) < 0.1, "black in light appearance")

        let dark = try components(of: color, inDarkAppearance: true)
        #expect(min(dark.red, dark.green, dark.blue) > 0.9, "white in dark appearance")
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
            #expect(converted, "expected an RGB-convertible color")
        #else
            let appearance = try #require(NSAppearance(named: isDark ? .darkAqua : .aqua))
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
