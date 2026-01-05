import Foundation
import CoreData
import Combine
import AVFoundation

class RecordingManager: ObservableObject {
    static let shared = RecordingManager()
    
    @Published var recordings: [Recording] = []
    @Published var folders: [Folder] = []
    
    private let context: NSManagedObjectContext
    private var cancellables = Set<AnyCancellable>()
    
    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.context = context
        loadRecordings()
        loadFolders()
    }
    
    @discardableResult
    func createRecording(title: String, audioURL: URL, duration: Double, location: String? = nil, transcript: String? = nil) -> Recording {
        let recording = Recording(context: context)
        recording.id = UUID()
        recording.title = title
        recording.createdAt = Date()
        recording.duration = duration
        recording.audioURL = audioURL
        recording.detectedSpeakers = 0
        recording.location = location
        recording.isProcessed = false
        if let transcript = transcript {
            recording.transcript = transcript
            
            // Calculate initial analytics
            let wordCount = AnalyticsService.shared.calculateWordCount(in: transcript)
            let fillerCount = AnalyticsService.shared.countFillerWords(in: transcript)
            
            recording.fillerWordCount = Int32(fillerCount)
            
            if duration > 0 {
                recording.wordsPerMinute = Double(wordCount) / (duration / 60.0)
            }
        }
        
        saveContext()
        loadRecordings()
        
        return recording
    }
    
    func updateRecording(_ recording: Recording, speakerSegments: [SpeakerSegmentInfo], transcript: String?) {
        recording.detectedSpeakers = Int16(Set(speakerSegments.map { $0.speakerId }).count)
        recording.transcript = transcript
        recording.isProcessed = true
        
        for segmentInfo in speakerSegments {
            let segment = SpeakerSegment(context: context)
            segment.id = UUID()
            segment.speakerId = segmentInfo.speakerId
            segment.startTime = segmentInfo.startTime
            segment.endTime = segmentInfo.endTime
            segment.confidence = segmentInfo.confidence
            segment.recording = recording
        }
        
        saveContext()
        loadRecordings()
    }
    
    // MARK: - Bookmarks
    
    @discardableResult
    func addBookmark(to recording: Recording, timestamp: TimeInterval, label: String, color: String = "#FF9500") -> Bookmark {
        let bookmark = Bookmark(context: context)
        bookmark.id = UUID()
        bookmark.timestamp = timestamp
        bookmark.label = label
        bookmark.color = color
        bookmark.recording = recording
        
        saveContext()
        return bookmark
    }
    
    func deleteBookmark(_ bookmark: Bookmark) {
        context.delete(bookmark)
        saveContext()
    }
    
    func getBookmarks(for recording: Recording) -> [Bookmark] {
        let set = recording.bookmarks as? Set<Bookmark> ?? []
        return set.sorted { $0.timestamp < $1.timestamp }
    }
    
    // MARK: - Analytics
    
    func updateAnalytics(_ recording: Recording, wordCount: Int, fillerWordCount: Int) {
        recording.fillerWordCount = Int32(fillerWordCount)
        
        // Calculate WPM
        let duration = recording.duration
        if duration > 0 {
            recording.wordsPerMinute = Double(wordCount) / (duration / 60.0)
        }
        
        saveContext()
    }
    
    func updateSpeakerSegmentTranscript(_ segment: SpeakerSegment, transcript: String, wordCount: Int) {
        segment.transcript = transcript
        segment.wordCount = Int32(wordCount)
        saveContext()
    }
    
    // MARK: - Delete
    
    func deleteRecording(_ recording: Recording) {
        if let audioURL = recording.audioURL {
            try? FileManager.default.removeItem(at: audioURL)
        }
        
        context.delete(recording)
        saveContext()
        loadRecordings()
    }
    
    // MARK: - Actions
    
    @discardableResult
    func duplicateRecording(_ recording: Recording) -> Recording? {
        guard let sourceURL = recording.audioURL else { return nil }
        let filename = (recording.title ?? "Recording") + " Copy"
        let destURL = sourceURL.deletingLastPathComponent()
            .appendingPathComponent((filename.replacingOccurrences(of: " ", with: "_")) + "_" + UUID().uuidString + ".wav")
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            let newRec = createRecording(
                title: filename,
                audioURL: destURL,
                duration: recording.duration,
                location: recording.location,
                transcript: recording.transcript
            )
            newRec.tags = recording.tags
            newRec.folder = recording.folder
            saveContext()
            loadRecordings()
            return newRec
        } catch {
            return nil
        }
    }
    
    func moveRecording(_ recording: Recording, to folder: Folder?) {
        recording.folder = folder
        saveContext()
        loadRecordings()
    }
    
    func toggleFavorite(_ recording: Recording) {
        var tags = (recording.tags ?? "")
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if let idx = tags.firstIndex(where: { $0.lowercased() == "favorite" }) {
            tags.remove(at: idx)
        } else {
            tags.append("favorite")
        }
        let unique = Array(Set(tags))
        recording.tags = unique.joined(separator: ",")
        saveContext()
        loadRecordings()
    }
    
    // MARK: - Folders
    
    @discardableResult
    func createFolder(name: String) -> Folder {
        let folder = Folder(context: context)
        folder.id = UUID()
        folder.name = name
        folder.createdAt = Date()
        
        saveContext()
        loadFolders()
        
        return folder
    }
    
    func deleteFolder(_ folder: Folder) {
        context.delete(folder)
        saveContext()
        loadFolders()
    }
    
    // MARK: - Load Data
    
    private func loadRecordings() {
        let request: NSFetchRequest<Recording> = Recording.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Recording.createdAt, ascending: false)]
        
        do {
            recordings = try context.fetch(request)
        } catch {
            print("Error loading recordings: \(error)")
        }
    }
    
    private func loadFolders() {
        let request: NSFetchRequest<Folder> = Folder.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Folder.name, ascending: true)]
        
        do {
            folders = try context.fetch(request)
        } catch {
            print("Error loading folders: \(error)")
        }
    }
    
    private func saveContext() {
        do {
            try context.save()
        } catch {
            print("Error saving context: \(error)")
        }
    }
    
    // MARK: - Search
    
    func searchRecordings(query: String) -> [Recording] {
        guard !query.isEmpty else { return recordings }
        
        return recordings.filter { recording in
            recording.title?.localizedCaseInsensitiveContains(query) == true ||
            recording.transcript?.localizedCaseInsensitiveContains(query) == true ||
            recording.tags?.localizedCaseInsensitiveContains(query) == true
        }
    }
}
