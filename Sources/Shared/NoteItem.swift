import Foundation
import SwiftData

@Model
final class NoteItem {
    @Attribute(.unique) var id: Int
    var colorHex: String
    var rtfData: Data
    
    init(id: Int, colorHex: String, rtfData: Data = Data()) {
        self.id = id
        self.colorHex = colorHex
        self.rtfData = rtfData
    }
}
