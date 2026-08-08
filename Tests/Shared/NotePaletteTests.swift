import Testing

@testable import Heptad

/// Pins the one thing about the palette that is not a taste question: there is exactly one
/// colour per note. Every reader indexes `colors` by note index, so a palette that is short
/// by one is an out-of-bounds crash at whichever note nobody happened to open in testing.
struct NotePaletteTests {

    @Test func thereIsOneColorPerNote() {
        #expect(NotePalette.colors.count == AppConstants.noteCount)
    }
}
