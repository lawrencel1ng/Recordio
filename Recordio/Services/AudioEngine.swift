import Foundation
import AVFoundation
import Combine

class AudioEngine: NSObject, ObservableObject {
    static let shared = AudioEngine()
    
    @Published var isRecording = false
    @Published var currentDuration: TimeInterval = 0
    @Published var audioLevel: Float = 0.0
    @Published var currentRecordingURL: URL?
    @Published var permissionGranted = false
    
    private var audioRecorder: AVAudioRecorder?
    private var recordingTimer: Timer?
    private var audioLevelTimer: Timer?
    private var startDate: Date?
    private var pauseDate: Date?
    private var pausedDuration: TimeInterval = 0
    
    private let sampleRate: Double = 48000.0
    private let channels: UInt32 = 1
    private let bitDepth: UInt32 = 24
    
    private var engineAudioEngine: AVAudioEngine?
    private var mixerNode: AVAudioMixerNode?
    
    var avAudioEngine: AVAudioEngine? {
        return engineAudioEngine
    }
    
    var isPaused: Bool {
        pauseDate != nil
    }
    
    private override init() {
        super.init()
        checkPermission()
    }
    
    // MARK: - Permission Handling
    
    func checkPermission() {
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                permissionGranted = true
            case .denied:
                permissionGranted = false
            case .undetermined:
                requestPermission()
            @unknown default:
                permissionGranted = false
            }
        } else {
            switch AVAudioSession.sharedInstance().recordPermission {
            case .granted:
                permissionGranted = true
            case .denied:
                permissionGranted = false
            case .undetermined:
                requestPermission()
            @unknown default:
                permissionGranted = false
            }
        }
    }
    
    func requestPermission() {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    self?.permissionGranted = granted
                }
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    self?.permissionGranted = granted
                }
            }
        }
    }
    
    // MARK: - Audio Session Configuration
    
    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
    }
    
    private func setupAudioEngine() {
        engineAudioEngine = AVAudioEngine()
        mixerNode = AVAudioMixerNode()
        
        guard let engine = engineAudioEngine,
              let mixer = mixerNode else {
            return
        }
        
        engine.attach(mixer)
        engine.connect(engine.inputNode, to: mixer, format: nil)
    }
    
    // MARK: - Recording
    
    func prepareRecording() throws {
        // Configure audio session first
        try configureAudioSession()
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recordingsPath = documentsPath.appendingPathComponent("Recordings", isDirectory: true)
        
        try FileManager.default.createDirectory(at: recordingsPath, withIntermediateDirectories: true)
        
        let filename = "Recording_\(Date().timeIntervalSince1970).wav"
        currentRecordingURL = recordingsPath.appendingPathComponent(filename)
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: bitDepth,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue
        ]
        
        audioRecorder = try AVAudioRecorder(url: currentRecordingURL!, settings: settings)
        audioRecorder?.delegate = self
        audioRecorder?.isMeteringEnabled = true
        audioRecorder?.prepareToRecord()
    }
    
    func startRecording() throws {
        guard permissionGranted else {
            requestPermission()
            throw RecordingError.permissionDenied
        }
        
        // Always prepare fresh for each recording
        try prepareRecording()
        
        // Setup AVAudioEngine for live transcription
        setupAudioEngine()
        
        do {
            try engineAudioEngine?.start()
        } catch {
            print("Failed to start AVAudioEngine: \(error)")
        }
        
        audioRecorder?.record()
        isRecording = true
        startDate = Date()
        currentDuration = 0
        
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateDuration()
        }
        
        audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateAudioLevel()
        }
    }
    
    func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
        
        recordingTimer?.invalidate()
        recordingTimer = nil
        audioLevelTimer?.invalidate()
        audioLevelTimer = nil
        
        engineAudioEngine?.stop()
        engineAudioEngine?.reset()
        engineAudioEngine = nil
        mixerNode = nil
        
        // Reset recorder for next recording
        audioRecorder = nil
        startDate = nil
        pauseDate = nil
        pausedDuration = 0
    }
    
    func pauseRecording() {
        guard isRecording, !isPaused else { return }
        
        audioRecorder?.pause()
        pauseDate = Date()
        
        recordingTimer?.invalidate()
        recordingTimer = nil
        audioLevelTimer?.invalidate()
        audioLevelTimer = nil
    }
    
    func resumeRecording() {
        guard isPaused, let recorder = audioRecorder else { return }
        
        recorder.record()
        
        if let pauseDate = pauseDate {
            pausedDuration += Date().timeIntervalSince(pauseDate)
            self.pauseDate = nil
        }
        
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateDuration()
        }
        
        audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateAudioLevel()
        }
    }
    
    private func updateDuration() {
        guard let startDate = startDate else { return }
        currentDuration = Date().timeIntervalSince(startDate)
    }
    
    private func updateAudioLevel() {
        audioRecorder?.updateMeters()
        audioLevel = audioRecorder?.averagePower(forChannel: 0) ?? -60.0
    }
    
    func getCurrentAmplitude() -> Float {
        let normalized = max(0, (audioLevel + 60) / 60)
        return Float(normalized)
    }
}

// MARK: - AVAudioRecorderDelegate

extension AudioEngine: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            if flag {
                NotificationCenter.default.post(name: .recordingDidFinish, object: self?.currentRecordingURL)
            }
        }
    }
    
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        print("Recording encode error: \(error?.localizedDescription ?? "Unknown error")")
        DispatchQueue.main.async { [weak self] in
            self?.stopRecording()
        }
    }
}

// MARK: - Errors

enum RecordingError: Error, LocalizedError {
    case permissionDenied
    case recordingFailed
    case noAudioFile
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission is required to record audio."
        case .recordingFailed:
            return "Failed to start recording."
        case .noAudioFile:
            return "No audio file was created."
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let recordingDidFinish = Notification.Name("recordingDidFinish")
}
