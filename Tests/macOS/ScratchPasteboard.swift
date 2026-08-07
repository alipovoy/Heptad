import AppKit
import Testing

/// A private `NSPasteboard` scoped to one test, released when it is deallocated.
///
/// Never `.general`: these suites write clipboards to read them back, and the clipboard of
/// whoever is running the tests is not theirs to overwrite. The UUID keeps the cases — which
/// Swift Testing runs in parallel — off each other's board.
///
/// A class rather than a struct, for the `deinit`: an unreleased named pasteboard outlives the
/// process inside `pasteboardd`.
final class ScratchPasteboard {
    let pasteboard: NSPasteboard

    init() {
        pasteboard = NSPasteboard(name: NSPasteboard.Name("HeptadTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
    }

    deinit {
        pasteboard.releaseGlobally()
    }

    /// Writes one item, replacing whatever was there. The flavors are the caller's to set: the
    /// point of every case using this is which of them the code under test settles on.
    func write(_ flavors: (NSPasteboardItem) -> Void) {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        flavors(item)
        pasteboard.writeObjects([item])
    }

    /// A clipboard carrying no text in any flavor, which both suites need a case for.
    ///
    /// Drawn as a real 1×1 bitmap: an `NSImage` with no representations has no TIFF data to
    /// write, so the resulting clipboard would be empty rather than image-only.
    func writeAnImage() throws {
        let bitmap = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0))
        let tiff = try #require(bitmap.tiffRepresentation)

        write { $0.setData(tiff, forType: .tiff) }
    }
}
