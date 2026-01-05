import Foundation
import CoreData

/// Service for calculating recording analytics
class AnalyticsService {
    static let shared = AnalyticsService()
    
    private init() {}
    
    // MARK: - Speaker Analytics
    
    struct SpeakerStats {
        let speakerId: Int16
        let speakingTime: Double
        let percentage: Double
        let wordCount: Int
        let averageWPM: Double
        let color: String
    }
    
    struct RecordingAnalytics {
        let totalDuration: Double
        let speakerStats: [SpeakerStats]
        let totalWords: Int
        let averageWPM: Double
        let silencePercentage: Double
        let fillerWordCount: Int
        let bookmarkCount: Int
    }
    
    func calculateAnalytics(for recording: Recording) -> RecordingAnalytics {
        let segments = recording.speakerSegmentsArray
        let duration = recording.duration
        
        // Calculate per-speaker statistics
        var speakerTimes: [Int16: Double] = [:]
        var speakerWords: [Int16: Int] = [:]
        
        for segment in segments {
            let segmentDuration = segment.endTime - segment.startTime
            speakerTimes[segment.speakerId, default: 0] += segmentDuration
            speakerWords[segment.speakerId, default: 0] += Int(segment.wordCount)
        }
        
        let totalSpeakingTime = speakerTimes.values.reduce(0, +)
        
        // Only calculate silence if we have speaker segment data
        let silencePercentage: Double
        if segments.isEmpty {
            silencePercentage = 0 // Can't determine silence without diarization data
        } else {
            let silenceTime = max(0, duration - totalSpeakingTime)
            silencePercentage = duration > 0 ? (silenceTime / duration) * 100 : 0
        }
        
        let speakerColors = ["#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4", "#FFEAA7", "#DDA0DD", "#98D8C8", "#F7DC6F"]
        
        // Calculate total words from segments
        var totalWords = speakerWords.values.reduce(0, +)
        
        // Fallback: If no segment word counts, calculate from transcript
        if totalWords == 0, let transcript = recording.transcript, !transcript.isEmpty {
            totalWords = calculateWordCount(in: transcript)
            
            // Distribute words proportionally to speaking time if we have segments
            if !segments.isEmpty && totalSpeakingTime > 0 {
                for (speakerId, time) in speakerTimes {
                    let proportion = time / totalSpeakingTime
                    speakerWords[speakerId] = Int(Double(totalWords) * proportion)
                }
            }
        }
        
        var speakerStats: [SpeakerStats] = []
        for (speakerId, time) in speakerTimes.sorted(by: { $0.key < $1.key }) {
            let percentage = duration > 0 ? (time / duration) * 100 : 0
            let words = speakerWords[speakerId] ?? 0
            let wpm = time > 0 ? Double(words) / (time / 60.0) : 0
            
            speakerStats.append(SpeakerStats(
                speakerId: speakerId,
                speakingTime: time,
                percentage: percentage,
                wordCount: words,
                averageWPM: wpm,
                color: speakerColors[Int(speakerId) % speakerColors.count]
            ))
        }
        
        // Calculate average WPM - use speaking time if available, otherwise use total duration
        let effectiveSpeakingTime = totalSpeakingTime > 0 ? totalSpeakingTime : duration
        var averageWPM = effectiveSpeakingTime > 0 ? Double(totalWords) / (effectiveSpeakingTime / 60.0) : 0
        
        // Fallback to recording's stored WPM if calculated is zero
        if averageWPM == 0 && recording.wordsPerMinute > 0 {
            averageWPM = recording.wordsPerMinute
        }
        
        let bookmarkCount = (recording.bookmarks as? Set<Bookmark>)?.count ?? 0
        
        return RecordingAnalytics(
            totalDuration: duration,
            speakerStats: speakerStats,
            totalWords: totalWords,
            averageWPM: averageWPM,
            silencePercentage: silencePercentage,
            fillerWordCount: Int(recording.fillerWordCount),
            bookmarkCount: bookmarkCount
        )
    }
    
    // MARK: - Filler Word Detection
    
    static let fillerWords = Set([
        "um", "uh", "er", "ah", "like", "you know", "basically",
        "actually", "literally", "right", "so", "well", "i mean",
        "kind of", "sort of", "you see", "okay so"
    ])
    
    func countFillerWords(in transcript: String) -> Int {
        let lowercased = transcript.lowercased()
        var count = 0
        
        for filler in Self.fillerWords {
            // Count occurrences with word boundaries
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: filler))\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                count += regex.numberOfMatches(in: lowercased, range: NSRange(lowercased.startIndex..., in: lowercased))
            }
        }
        
        return count
    }
    
    func detectFillerWords(in transcript: String) -> [(word: String, range: Range<String.Index>)] {
        let lowercased = transcript.lowercased()
        var results: [(String, Range<String.Index>)] = []
        
        for filler in Self.fillerWords {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: filler))\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let matches = regex.matches(in: transcript, range: NSRange(transcript.startIndex..., in: transcript))
                for match in matches {
                    if let range = Range(match.range, in: transcript) {
                        results.append((filler, range))
                    }
                }
            }
        }
        
        return results.sorted { $0.1.lowerBound < $1.1.lowerBound }
    }
    
    // MARK: - Word Count & WPM
    
    func calculateWordCount(in transcript: String) -> Int {
        let words = transcript.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        return words.count
    }
    
    func calculateWPM(wordCount: Int, duration: Double) -> Double {
        guard duration > 0 else { return 0 }
        return Double(wordCount) / (duration / 60.0)
    }
    
    // MARK: - Silence Detection
    
    struct SilenceMarker: Identifiable {
        let id = UUID()
        let startTime: Double
        let endTime: Double
        var duration: Double { endTime - startTime }
    }
    
    func detectSilences(in segments: [SpeakerSegment], totalDuration: Double, minSilenceDuration: Double = 3.0) -> [SilenceMarker] {
        // If no segments, we can't detect silences (no timing data)
        guard !segments.isEmpty else { return [] }
        
        var silences: [SilenceMarker] = []
        
        let sortedSegments = segments.sorted { $0.startTime < $1.startTime }
        var lastEndTime: Double = 0
        
        for segment in sortedSegments {
            let gap = segment.startTime - lastEndTime
            if gap >= minSilenceDuration {
                silences.append(SilenceMarker(startTime: lastEndTime, endTime: segment.startTime))
            }
            lastEndTime = max(lastEndTime, segment.endTime)
        }
        
        // Check for silence at the end (only if segments cover some of the recording)
        if lastEndTime > 0 && totalDuration - lastEndTime >= minSilenceDuration {
            silences.append(SilenceMarker(startTime: lastEndTime, endTime: totalDuration))
        }
        
        return silences
    }
}
