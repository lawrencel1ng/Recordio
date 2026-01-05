import Foundation
import CoreData

extension Recording {
    var speakerSegmentsArray: [SpeakerSegment] {
        let set = speakerSegments as? Set<SpeakerSegment> ?? []
        return set.sorted { $0.startTime < $1.startTime }
    }
    
    var tagsArray: [String] {
        tags?.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
    }
}

extension SpeakerSegment {
    var speakerColor: String {
        let colors = ["#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4", "#FFEAA7", "#DDA0DD", "#98D8C8", "#F7DC6F"]
        return colors[Int(speakerId) % colors.count]
    }
}
