import Foundation
import Speech
import AVFoundation
import Combine

/// Service for real-time speech transcription during recording
class LiveTranscriptionService: ObservableObject {
    static let shared = LiveTranscriptionService()
    
    @Published var liveTranscript: String = ""
    @Published var isTranscribing = false
    @Published var transcriptionSegments: [TranscriptSegment] = []
    
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    
    private var startTime: Date?
    
    private init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }
    
    // MARK: - Authorization
    
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                completion(status == .authorized)
            }
        }
    }
    
    var isAuthorized: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }
    
    // MARK: - Live Transcription
    
    func startLiveTranscription(audioEngine: AVAudioEngine) throws {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            throw LiveTranscriptionError.recognizerUnavailable
        }
        
        // Cancel any ongoing task
        stopLiveTranscription()
        
        self.audioEngine = audioEngine
        self.startTime = Date()
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw LiveTranscriptionError.requestCreationFailed
        }
        
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.taskHint = .dictation
        
        // Enable on-device recognition if available (iOS 13+)
        if #available(iOS 13.0, *) {
            recognitionRequest.requiresOnDeviceRecognition = speechRecognizer.supportsOnDeviceRecognition
        }
        
        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                DispatchQueue.main.async {
                    self.liveTranscript = result.bestTranscription.formattedString
                    
                    // Update segments
                    self.updateSegments(from: result.bestTranscription)
                }
            }
            
            if error != nil || result?.isFinal == true {
                DispatchQueue.main.async {
                    self.isTranscribing = false
                }
            }
        }
        
        // Install audio tap
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        
        isTranscribing = true
    }
    
    func stopLiveTranscription() {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        audioEngine?.inputNode.removeTap(onBus: 0)
        
        recognitionRequest = nil
        recognitionTask = nil
        isTranscribing = false
    }
    
    private func updateSegments(from transcription: SFTranscription) {
        guard let startTime = startTime else { return }
        
        var segments: [TranscriptSegment] = []
        
        for segment in transcription.segments {
            let transcriptSegment = TranscriptSegment(
                text: segment.substring,
                timestamp: segment.timestamp,
                duration: segment.duration,
                confidence: Double(segment.confidence)
            )
            segments.append(transcriptSegment)
        }
        
        transcriptionSegments = segments
    }
    
    func reset() {
        liveTranscript = ""
        transcriptionSegments = []
        startTime = nil
    }
}

// MARK: - Models

struct TranscriptSegment: Identifiable {
    let id = UUID()
    let text: String
    let timestamp: TimeInterval
    let duration: TimeInterval
    let confidence: Double
}

// MARK: - Errors

enum LiveTranscriptionError: Error, LocalizedError {
    case recognizerUnavailable
    case requestCreationFailed
    case notAuthorized
    
    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "Speech recognizer is not available"
        case .requestCreationFailed:
            return "Failed to create recognition request"
        case .notAuthorized:
            return "Speech recognition is not authorized"
        }
    }
}
