import Testing

@testable import Heptad

/// Pins the one thing about the palette that is not a taste question: there is exactly one
/// colour per note. Every reader indexes `colors` by note index, so a palette that is short
/// by one is an out-of-bounds crash at whichever note nobody happened to open in testing.
struct NotePaletteTests {

    @Test func thereIsOneColorPerNote() {
        #expect(NotePalette.colors.count == AppConstants.noteCount)
    }

    /// Two notes drawn in the same colour would make the circles ambiguous, which is the
    /// only way the row says which note is which before one is opened.
    @Test func everyColorIsDistinct() {
        #expect(Set(NotePalette.colors.map(String.init(describing:))).count == NotePalette.colors.count)
    }
}
