import Foundation
import CoreData

/// Service for full-text search across recordings
class SearchService {
    static let shared = SearchService()
    
    private init() {}
    
    struct SearchResult: Identifiable {
        let id: UUID
        let recording: Recording
        let matchType: MatchType
        let matchedText: String
        let contextSnippet: String
        
        enum MatchType {
            case title
            case transcript
            case tag
        }
    }
    
    /// Search recordings by query across titles, transcripts, and tags
    func search(query: String, in context: NSManagedObjectContext) -> [SearchResult] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return []
        }
        
        let searchTerms = query.lowercased().split(separator: " ").map(String.init)
        var results: [SearchResult] = []
        
        // Fetch all recordings
        let request = NSFetchRequest<Recording>(entityName: "Recording")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Recording.createdAt, ascending: false)]
        
        guard let recordings = try? context.fetch(request) else {
            return []
        }
        
        for recording in recordings {
            // Search in title
            if let title = recording.title?.lowercased(),
               searchTerms.allSatisfy({ title.contains($0) }) {
                results.append(SearchResult(
                    id: UUID(),
                    recording: recording,
                    matchType: .title,
                    matchedText: recording.title ?? "",
                    contextSnippet: recording.title ?? ""
                ))
                continue // Don't duplicate recording in results
            }
            
            // Search in transcript
            if let transcript = recording.transcript?.lowercased(),
               searchTerms.allSatisfy({ transcript.contains($0) }) {
                let snippet = extractSnippet(from: recording.transcript ?? "", containing: query)
                results.append(SearchResult(
                    id: UUID(),
                    recording: recording,
                    matchType: .transcript,
                    matchedText: query,
                    contextSnippet: snippet
                ))
                continue
            }
            
            // Search in tags
            if let tags = recording.tags?.lowercased(),
               searchTerms.allSatisfy({ tags.contains($0) }) {
                results.append(SearchResult(
                    id: UUID(),
                    recording: recording,
                    matchType: .tag,
                    matchedText: recording.tags ?? "",
                    contextSnippet: recording.tags ?? ""
                ))
            }
        }
        
        return results
    }
    
    /// Extract a snippet around the matched text
    private func extractSnippet(from text: String, containing query: String, contextLength: Int = 50) -> String {
        let lowercased = text.lowercased()
        let queryLower = query.lowercased()
        
        guard let range = lowercased.range(of: queryLower) else {
            // Return start of text if query not found
            return String(text.prefix(contextLength * 2)) + "..."
        }
        
        let matchStart = text.distance(from: text.startIndex, to: range.lowerBound)
        let snippetStart = max(0, matchStart - contextLength)
        let snippetEnd = min(text.count, matchStart + query.count + contextLength)
        
        let startIndex = text.index(text.startIndex, offsetBy: snippetStart)
        let endIndex = text.index(text.startIndex, offsetBy: snippetEnd)
        
        var snippet = String(text[startIndex..<endIndex])
        
        if snippetStart > 0 {
            snippet = "..." + snippet
        }
        if snippetEnd < text.count {
            snippet = snippet + "..."
        }
        
        return snippet
    }
    
    /// Get recordings with transcripts containing specific filler words
    func findRecordingsWithFillerWords(in context: NSManagedObjectContext) -> [Recording] {
        let request = NSFetchRequest<Recording>(entityName: "Recording")
        request.predicate = NSPredicate(format: "fillerWordCount > 0")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Recording.fillerWordCount, ascending: false)]
        
        return (try? context.fetch(request)) ?? []
    }
    
    /// Get recent recordings matching search
    func recentRecordingsMatching(query: String, limit: Int = 5, in context: NSManagedObjectContext) -> [Recording] {
        let results = search(query: query, in: context)
        return Array(results.prefix(limit).map { $0.recording })
    }
}
