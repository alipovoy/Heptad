import Foundation
import SwiftData

@Model
final class NoteItem {
    @Attribute(.unique) var id: Int
    var rtfData: Data
    
    init(id: Int, rtfData: Data = Data()) {
        self.id = id
        self.rtfData = rtfData
    }
}
