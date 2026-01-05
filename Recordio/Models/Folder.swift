import Foundation
import CoreData

extension Folder {
    var recordingsArray: [Recording] {
        let set = recordings as? Set<Recording> ?? []
        return set.sorted { ($0.createdAt ?? Date.distantPast) > ($1.createdAt ?? Date.distantPast) }
    }
}

enum SmartFolder: String, CaseIterable {
    case all = "All Recordings"
    case recent = "Recent"
    case favorites = "Favorites"
    case meetings = "Meetings"
    case lectures = "Lectures"
    case interviews = "Interviews"
}
