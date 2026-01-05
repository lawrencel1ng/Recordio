import Foundation
import AVFoundation
import Speech

// MARK: - Transcription Result

struct TranscriptionResult {
    let fullTranscript: String
    let segmentTranscripts: [SegmentTranscript]
}

struct SegmentTranscript {
    let speakerId: Int16
    let text: String
    let wordCount: Int
}

class TranscriptionService {
    static let shared = TranscriptionService()
    
    private let speechRecognizer: SFSpeechRecognizer?
    private var isAuthorized = false
    
    private init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        checkAuthorization()
    }
    
    // MARK: - Authorization
    
    private func checkAuthorization() {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            isAuthorized = true
        case .notDetermined:
            requestAuthorization()
        case .denied, .restricted:
            isAuthorized = false
        @unknown default:
            isAuthorized = false
        }
    }
    
    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.isAuthorized = (status == .authorized)
                completion?(status == .authorized)
            }
        }
    }
    
    // MARK: - Transcription
    
    func transcribeAudioFile(_ url: URL, speakerSegments: [SpeakerSegmentInfo], completion: @escaping (Result<TranscriptionResult, Error>) -> Void) {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            completion(.failure(TranscriptionError.recognizerUnavailable))
            return
        }
        
        guard isAuthorized else {
            requestAuthorization { [weak self] authorized in
                if authorized {
                    self?.performTranscription(url: url, speakerSegments: speakerSegments, completion: completion)
                } else {
                    completion(.failure(TranscriptionError.notAuthorized))
                }
            }
            return
        }
        
        performTranscription(url: url, speakerSegments: speakerSegments, completion: completion)
    }
    
    private func performTranscription(url: URL, speakerSegments: [SpeakerSegmentInfo], completion: @escaping (Result<TranscriptionResult, Error>) -> Void) {
        AppLogger.shared.logEvent(AppLogger.Events.transcriptionStarted)
        
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        
        // Enable automatic punctuation if available
        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }
        
        speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                if let error = error {
                    // Check if it's a cancellation or actual error
                    let nsError = error as NSError
                    if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110 {
                        // No speech detected - return empty transcript
                        completion(.success(TranscriptionResult(fullTranscript: "", segmentTranscripts: [])))
                    } else {
                        AppLogger.shared.logError(error, additionalInfo: ["context": "transcription"])
                        AppLogger.shared.logEvent(AppLogger.Events.transcriptionFailed, parameters: [
                            AppLogger.Params.errorDescription: error.localizedDescription
                        ])
                        completion(.failure(error))
                    }
                    return
                }
                
                guard let result = result else {
                    completion(.failure(TranscriptionError.noResult))
                    return
                }
                
                if result.isFinal {
                    AppLogger.shared.logEvent(AppLogger.Events.transcriptionCompleted, parameters: [
                        AppLogger.Params.wordCount: result.bestTranscription.segments.count
                    ])
                    
                    let fullTranscript = result.bestTranscription.formattedString
                    
                    // Format transcript with speaker labels if segments available
                    if !speakerSegments.isEmpty {
                        let (formattedTranscript, segmentTranscripts) = self?.formatWithSpeakers(
                            transcript: fullTranscript,
                            segments: result.bestTranscription.segments,
                            speakerSegments: speakerSegments
                        ) ?? (fullTranscript, [])
                        
                        let transcriptionResult = TranscriptionResult(
                            fullTranscript: formattedTranscript,
                            segmentTranscripts: segmentTranscripts
                        )
                        completion(.success(transcriptionResult))
                    } else {
                        let transcriptionResult = TranscriptionResult(
                            fullTranscript: fullTranscript,
                            segmentTranscripts: []
                        )
                        completion(.success(transcriptionResult))
                    }
                }
            }
        }
    }
    
    private func formatWithSpeakers(transcript: String, segments: [SFTranscriptionSegment], speakerSegments: [SpeakerSegmentInfo]) -> (String, [SegmentTranscript]) {
        guard !segments.isEmpty, !speakerSegments.isEmpty else {
            return (transcript, [])
        }
        
        var formattedTranscript = ""
        var segmentTranscripts: [SegmentTranscript] = []
        var currentSpeaker: Int16 = -1
        var currentText = ""
        var currentTimestamp: Double = 0
        
        // Helper to save current speaker segment
        func saveCurrentSegment() {
            if !currentText.isEmpty {
                let trimmedText = currentText.trimmingCharacters(in: .whitespaces)
                let timestamp = formatTimestamp(currentTimestamp)
                formattedTranscript += "[\(timestamp)] Speaker \(currentSpeaker + 1): \(trimmedText)\n\n"
                
                // Calculate word count for this segment
                let words = trimmedText.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
                segmentTranscripts.append(SegmentTranscript(
                    speakerId: currentSpeaker,
                    text: trimmedText,
                    wordCount: words.count
                ))
            }
        }
        
        for segment in segments {
            let segmentTime = segment.timestamp
            
            // Find which speaker this segment belongs to
            let speaker = findSpeaker(for: segmentTime, in: speakerSegments)
            
            if speaker != currentSpeaker {
                // Save previous speaker's segment
                saveCurrentSegment()
                
                // Start new speaker section
                currentSpeaker = speaker
                currentText = segment.substring
                currentTimestamp = segmentTime
            } else {
                currentText += " " + segment.substring
            }
        }
        
        // Save final speaker's segment
        saveCurrentSegment()
        
        // Remove trailing newlines from formatted transcript
        formattedTranscript = formattedTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return (formattedTranscript.isEmpty ? transcript : formattedTranscript, segmentTranscripts)
    }
    
    private func findSpeaker(for timestamp: Double, in segments: [SpeakerSegmentInfo]) -> Int16 {
        for segment in segments {
            if timestamp >= segment.startTime && timestamp < segment.endTime {
                return segment.speakerId
            }
        }
        return segments.first?.speakerId ?? 0
    }
    
    private func formatTimestamp(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}

// MARK: - Errors

enum TranscriptionError: Error, LocalizedError {
    case noAudioFile
    case transcriptionFailed
    case recognizerUnavailable
    case notAuthorized
    case noResult
    
    var errorDescription: String? {
        switch self {
        case .noAudioFile:
            return "No audio file found"
        case .transcriptionFailed:
            return "Failed to transcribe audio"
        case .recognizerUnavailable:
            return "Speech recognizer is not available"
        case .notAuthorized:
            return "Speech recognition is not authorized"
        case .noResult:
            return "No transcription result received"
        }
    }
}
