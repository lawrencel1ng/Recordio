import Foundation
import AVFoundation
import Combine
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

class AudioEngine: NSObject, ObservableObject {
    static let shared = AudioEngine()
    
    @Published var isRecording = false
    @Published var currentDuration: TimeInterval = 0
    @Published var audioLevel: Float = 0.0
    @Published var currentRecordingURL: URL?
    @Published var permissionGranted = false
    @Published var systemWarning: String?
    
    private var audioRecorder: AVAudioRecorder?
    private var recordingTimer: Timer?
    private var audioLevelTimer: Timer?
    private var startDate: Date?
    private var pauseDate: Date?
    private var pausedDuration: TimeInterval = 0
    private var partURLs: [URL] = []
    private var partIndex: Int = 1
    
    private var sampleRate: Double = 48000.0
    private var channels: UInt32 = 1
    private var bitDepth: UInt32 = 24
    
    private var engineAudioEngine: AVAudioEngine?
    private var mixerNode: AVAudioMixerNode?
    private var prebufferSamples: [Float] = []
    private var isPrebuffering = false
    
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
        if engineAudioEngine == nil {
            engineAudioEngine = AVAudioEngine()
            mixerNode = AVAudioMixerNode()
        }
        
        guard let engine = engineAudioEngine,
              let mixer = mixerNode else {
            return
        }
        
        if mixer.engine == nil {
            engine.attach(mixer)
            engine.connect(engine.inputNode, to: mixer, format: nil)
        }
    }
    
    // MARK: - Recording
    
    func prepareRecording() throws {
        // Configure audio session first
        try configureAudioSession()
        
        try preflightStorage()
        
        applyRecordingProfile()
        
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
    
    private func preflightStorage() throws {
        evaluateSystemConditions()
        let freeBytes = Self.freeDiskSpaceBytes()
        // Estimate bytes per second based on current profile
        let bytesPerSecond = Int(sampleRate) * Int(bitDepth / 8) * Int(channels)
        // Require at least 100MB or 10 minutes of recording, whichever is larger
        let minRequired = max(100 * 1024 * 1024, bytesPerSecond * 600)
        if freeBytes < minRequired {
            throw RecordingError.lowDiskSpace
        }
    }
    
    private func evaluateSystemConditions() {
        #if os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        let batteryLevel = UIDevice.current.batteryLevel
        let batteryState = UIDevice.current.batteryState
        if batteryState == .unplugged && batteryLevel >= 0 && batteryLevel < 0.1 {
            systemWarning = "Low battery may affect recording stability."
        }
        #endif
        let thermal = ProcessInfo.processInfo.thermalState
        if thermal == .serious || thermal == .critical {
            systemWarning = "High device temperature detected. Performance may be reduced."
        }
    }
    
    static func freeDiskSpaceBytes() -> Int {
        let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        guard let path = paths.first else { return 0 }
        do {
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: path)
            let freeSize = attributes[.systemFreeSize] as? NSNumber
            return freeSize?.intValue ?? 0
        } catch {
            return 0
        }
    }
    
    private func applyRecordingProfile() {
        let profile = UserDefaults.standard.string(forKey: "recordingProfile") ?? "lecture"
        switch profile {
        case "voice":
            sampleRate = 44100.0
            bitDepth = 16
            channels = 1
        case "music":
            sampleRate = 96000.0
            bitDepth = 24
            channels = 2
        case "field":
            sampleRate = 48000.0
            bitDepth = 24
            channels = 2
        default:
            sampleRate = 48000.0
            bitDepth = 24
            channels = 1
        }
    }
    
    // MARK: - Prebuffer (Pre-roll)
    
    @AppStorage("prebufferSeconds") var prebufferSeconds: Int = 0
    
    func startPrebuffering() throws {
        guard prebufferSeconds > 0 else { return }
        guard !isPrebuffering else { return }
        try configureAudioSession()
        setupAudioEngine()
        let inputNode = engineAudioEngine!.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }
            let channelData = buffer.floatChannelData
            let frameCount = Int(buffer.frameLength)
            if let data = channelData {
                let channel0 = data[0]
                for i in 0..<frameCount {
                    let sample = channel0[i]
                    self.appendPrebufferSample(sample)
                }
            }
        }
        try engineAudioEngine?.start()
        isPrebuffering = true
    }
    
    func stopPrebuffering() {
        guard isPrebuffering else { return }
        engineAudioEngine?.inputNode.removeTap(onBus: 0)
        isPrebuffering = false
    }
    
    private func appendPrebufferSample(_ s: Float) {
        let maxSamples = Int(Double(prebufferSeconds) * sampleRate)
        prebufferSamples.append(s)
        if prebufferSamples.count > maxSamples {
            let overflow = prebufferSamples.count - maxSamples
            prebufferSamples.removeFirst(overflow)
        }
    }
    
    func hasPrebuffer() -> Bool {
        return prebufferSeconds > 0 && !prebufferSamples.isEmpty
    }
    
    func exportPrebufferToFile() throws -> URL {
        guard hasPrebuffer() else { throw RecordingError.noAudioFile }
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let outputPath = documentsPath.appendingPathComponent("Edited", isDirectory: true)
        try FileManager.default.createDirectory(at: outputPath, withIntermediateDirectories: true)
        let outURL = outputPath.appendingPathComponent("PreRoll_\(UUID().uuidString).wav")
        let channels: AVAudioChannelCount = 1
        guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: channels, interleaved: false) else {
            throw RecordingError.recordingFailed
        }
        guard let file = try? AVAudioFile(forWriting: outURL, settings: [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]) else {
            throw RecordingError.recordingFailed
        }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(prebufferSamples.count)) else {
            throw RecordingError.recordingFailed
        }
        buffer.frameLength = AVAudioFrameCount(prebufferSamples.count)
        if let int16Data = buffer.int16ChannelData {
            let dest = int16Data[0]
            for i in 0..<prebufferSamples.count {
                let clamped = max(-1.0, min(1.0, prebufferSamples[i]))
                dest[i] = Int16(clamped * Float(Int16.max))
            }
        }
        try file.write(from: buffer)
        return outURL
    }
    
    func startRecording() throws {
        guard permissionGranted else {
            requestPermission()
            throw RecordingError.permissionDenied
        }
        
        // Always prepare fresh for each recording
        try prepareRecording()
        partURLs = []
        partIndex = 1
        
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
        
        AppLogger.shared.logEvent(AppLogger.Events.recordingStarted)
        
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
        
        AppLogger.shared.logEvent(AppLogger.Events.recordingStopped, parameters: [
            AppLogger.Params.duration: currentDuration
        ])
        
        recordingTimer?.invalidate()
        recordingTimer = nil
        audioLevelTimer?.invalidate()
        audioLevelTimer = nil
        
        engineAudioEngine?.stop()
        engineAudioEngine?.reset()
        engineAudioEngine = nil
        mixerNode = nil
        isPrebuffering = false
        prebufferSamples = []
        
        if !partURLs.isEmpty, let finalURL = mergePartsIfNeeded() {
            currentRecordingURL = finalURL
            NotificationCenter.default.post(name: .recordingDidFinish, object: finalURL)
        }
        
        // Reset recorder for next recording
        audioRecorder = nil
        startDate = nil
        pauseDate = nil
        pausedDuration = 0
    }
    
    private func mergePartsIfNeeded() -> URL? {
        var urls = partURLs
        if let currentURL = currentRecordingURL {
            urls.append(currentURL)
        }
        guard !urls.isEmpty else { return nil }
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let outputPath = documentsPath.appendingPathComponent("Edited", isDirectory: true)
        try? FileManager.default.createDirectory(at: outputPath, withIntermediateDirectories: true)
        let mergedURL = outputPath.appendingPathComponent("Merged_\(UUID().uuidString).m4a")
        if (try? AudioEditorService.shared.mergeAudio(recordings: urls, outputURL: mergedURL)) != nil {
            return mergedURL
        }
        return nil
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
        checkForRolloverIfNeeded()
    }
    
    @AppStorage("maxFileSizeMB") var maxFileSizeMB: Int = 0
    
    private func checkForRolloverIfNeeded() {
        guard maxFileSizeMB > 0, let url = currentRecordingURL else { return }
        let threshold = maxFileSizeMB * 1024 * 1024
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? NSNumber,
           size.intValue >= threshold {
            rolloverRecordingPart()
        }
    }
    
    private func rolloverRecordingPart() {
        guard let currentURL = currentRecordingURL else { return }
        audioRecorder?.stop()
        partURLs.append(currentURL)
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recordingsPath = documentsPath.appendingPathComponent("Recordings", isDirectory: true)
        let filename = "Recording_\(Date().timeIntervalSince1970)_part\(partIndex).wav"
        currentRecordingURL = recordingsPath.appendingPathComponent(filename)
        partIndex += 1
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: bitDepth,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: currentRecordingURL!, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.prepareToRecord()
            audioRecorder?.record()
        } catch {
        }
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
        if let error = error {
            AppLogger.shared.logError(error, additionalInfo: ["context": "audioRecorderEncodeError"])
        }
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
    case lowDiskSpace
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission is required to record audio."
        case .recordingFailed:
            return "Failed to start recording."
        case .noAudioFile:
            return "No audio file was created."
        case .lowDiskSpace:
            return "Low storage space. Free up space to record safely."
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let recordingDidFinish = Notification.Name("recordingDidFinish")
    static let quickCaptureRequested = Notification.Name("quickCaptureRequested")
}
