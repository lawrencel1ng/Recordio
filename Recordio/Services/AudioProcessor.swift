import Foundation
import AVFoundation
import Accelerate
import Combine

/// Service for audio processing - enhancement, noise reduction, and speaker track export
class AudioProcessor: ObservableObject {
    static let shared = AudioProcessor()
    
    @Published var isProcessing = false
    @Published var processingProgress: Float = 0.0
    
    private init() {}
    
    // MARK: - Audio Enhancement
    
    /// Enhance audio by normalizing levels and applying subtle compression
    func enhanceAudio(url: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        isProcessing = true
        processingProgress = 0.0
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let outputURL = try self?.normalizeAndEnhance(inputURL: url)
                DispatchQueue.main.async {
                    self?.isProcessing = false
                    self?.processingProgress = 1.0
                    if let output = outputURL {
                        completion(.success(output))
                    } else {
                        completion(.failure(AudioProcessingError.exportSessionFailed))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.isProcessing = false
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Noise Reduction
    
    /// Reduce background noise using noise gate and frequency filtering
    func reduceNoise(url: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        isProcessing = true
        processingProgress = 0.0
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let outputURL = try self?.applyNoiseReduction(inputURL: url)
                DispatchQueue.main.async {
                    self?.isProcessing = false
                    self?.processingProgress = 1.0
                    if let output = outputURL {
                        completion(.success(output))
                    } else {
                        completion(.failure(AudioProcessingError.exportSessionFailed))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.isProcessing = false
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Speaker Track Export
    
    func exportSpeakerTrack(url: URL, speakerId: Int16, segments: [SpeakerSegment], completion: @escaping (Result<URL, Error>) -> Void) {
        isProcessing = true
        processingProgress = 0.0
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let outputURL = try self?.extractSpeakerTrack(url: url, speakerId: speakerId, segments: segments)
                DispatchQueue.main.async {
                    self?.isProcessing = false
                    self?.processingProgress = 1.0
                    if let output = outputURL {
                        completion(.success(output))
                    } else {
                        completion(.failure(AudioProcessingError.exportSessionFailed))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.isProcessing = false
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Audio Processing Implementations
    
    private func normalizeAndEnhance(inputURL: URL) throws -> URL {
        let audioFile = try AVAudioFile(forReading: inputURL)
        let format = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)
        
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw AudioProcessingError.compositionError
        }
        
        try audioFile.read(into: inputBuffer)
        
        // Get audio data
        guard let floatData = inputBuffer.floatChannelData else {
            throw AudioProcessingError.noAudioTrack
        }
        
        let channelCount = Int(format.channelCount)
        let frameLength = Int(inputBuffer.frameLength)
        
        // Process each channel
        for channel in 0..<channelCount {
            let samples = floatData[channel]
            
            // Find peak amplitude
            var peak: Float = 0.0
            vDSP_maxmgv(samples, 1, &peak, vDSP_Length(frameLength))
            
            // Normalize to 0.95 peak (leave headroom)
            if peak > 0.001 {
                let targetPeak: Float = 0.95
                var gain = targetPeak / peak
                vDSP_vsmul(samples, 1, &gain, samples, 1, vDSP_Length(frameLength))
            }
            
            // Apply subtle soft-knee compression
            for i in 0..<frameLength {
                let sample = samples[i]
                let threshold: Float = 0.7
                let ratio: Float = 4.0
                
                if abs(sample) > threshold {
                    let excess = abs(sample) - threshold
                    let compressed = threshold + (excess / ratio)
                    samples[i] = sample > 0 ? compressed : -compressed
                }
            }
            
            updateProgress(Float(channel + 1) / Float(channelCount) * 0.8)
        }
        
        // Create output file
        let outputURL = generateOutputURL(from: inputURL, suffix: "_enhanced")
        try? FileManager.default.removeItem(at: outputURL)
        
        let outputFile = try AVAudioFile(forWriting: outputURL, settings: audioFile.fileFormat.settings)
        try outputFile.write(from: inputBuffer)
        
        updateProgress(1.0)
        return outputURL
    }
    
    private func applyNoiseReduction(inputURL: URL) throws -> URL {
        let audioFile = try AVAudioFile(forReading: inputURL)
        let format = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)
        
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw AudioProcessingError.compositionError
        }
        
        try audioFile.read(into: inputBuffer)
        
        guard let floatData = inputBuffer.floatChannelData else {
            throw AudioProcessingError.noAudioTrack
        }
        
        let channelCount = Int(format.channelCount)
        let frameLength = Int(inputBuffer.frameLength)
        
        // Noise gate parameters
        let noiseFloor: Float = 0.02  // Below this is considered noise
        let attackTime: Float = 0.005  // 5ms attack
        let releaseTime: Float = 0.1   // 100ms release
        let sampleRate = Float(format.sampleRate)
        
        let attackCoeff = expf(-1.0 / (attackTime * sampleRate))
        let releaseCoeff = expf(-1.0 / (releaseTime * sampleRate))
        
        for channel in 0..<channelCount {
            let samples = floatData[channel]
            var envelope: Float = 0.0
            
            // Apply noise gate with envelope follower
            for i in 0..<frameLength {
                let inputAbs = abs(samples[i])
                
                // Envelope follower
                if inputAbs > envelope {
                    envelope = attackCoeff * envelope + (1 - attackCoeff) * inputAbs
                } else {
                    envelope = releaseCoeff * envelope + (1 - releaseCoeff) * inputAbs
                }
                
                // Apply gain based on envelope
                var gain: Float = 1.0
                if envelope < noiseFloor {
                    gain = envelope / noiseFloor  // Smooth attenuation
                }
                
                samples[i] *= gain
            }
            
            updateProgress(Float(channel + 1) / Float(channelCount) * 0.8)
        }
        
        // Create output file
        let outputURL = generateOutputURL(from: inputURL, suffix: "_denoised")
        try? FileManager.default.removeItem(at: outputURL)
        
        let outputFile = try AVAudioFile(forWriting: outputURL, settings: audioFile.fileFormat.settings)
        try outputFile.write(from: inputBuffer)
        
        updateProgress(1.0)
        return outputURL
    }
    
    private func extractSpeakerTrack(url: URL, speakerId: Int16, segments: [SpeakerSegment]) throws -> URL {
        let asset = AVURLAsset(url: url)
        let outputURL = generateOutputURL(from: url, suffix: "_speaker\(speakerId)")
        
        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw AudioProcessingError.compositionError
        }
        
        guard let assetTrack = asset.tracks(withMediaType: .audio).first else {
            throw AudioProcessingError.noAudioTrack
        }
        
        var currentTime = CMTime.zero
        let speakerSegments = segments.filter { $0.speakerId == speakerId }.sorted { $0.startTime < $1.startTime }
        
        for (index, segment) in speakerSegments.enumerated() {
            let segmentStart = CMTime(seconds: segment.startTime, preferredTimescale: 1000)
            let segmentDuration = CMTime(seconds: segment.endTime - segment.startTime, preferredTimescale: 1000)
            
            try compositionTrack.insertTimeRange(
                CMTimeRange(start: segmentStart, duration: segmentDuration),
                of: assetTrack,
                at: currentTime
            )
            
            currentTime = CMTimeAdd(currentTime, segmentDuration)
            updateProgress(Float(index + 1) / Float(speakerSegments.count))
        }
        
        // Export
        try? FileManager.default.removeItem(at: outputURL)
        
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw AudioProcessingError.exportSessionFailed
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        
        let semaphore = DispatchSemaphore(value: 0)
        var exportError: Error?
        
        exportSession.exportAsynchronously {
            if exportSession.status == .failed {
                exportError = exportSession.error
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        if let error = exportError {
            throw error
        }
        
        return outputURL
    }
    
    // MARK: - Helpers
    
    private func generateOutputURL(from inputURL: URL, suffix: String) -> URL {
        let directory = inputURL.deletingLastPathComponent()
        let filename = inputURL.deletingPathExtension().lastPathComponent
        return directory.appendingPathComponent("\(filename)\(suffix).m4a")
    }
    
    private func updateProgress(_ progress: Float) {
        DispatchQueue.main.async { [weak self] in
            self?.processingProgress = progress
        }
    }
}

// MARK: - Errors

enum AudioProcessingError: Error, LocalizedError {
    case noAudioTrack
    case compositionError
    case exportSessionFailed
    case processingFailed
    
    var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            return "No audio track found in recording"
        case .compositionError:
            return "Failed to create audio composition"
        case .exportSessionFailed:
            return "Failed to export processed audio"
        case .processingFailed:
            return "Audio processing failed"
        }
    }
}

enum ProcessingType: String {
    case enhancement
    case noiseReduction
}
