import Foundation
import AVFoundation
import Accelerate

class SpeakerDiarizationService {
    static let shared = SpeakerDiarizationService()
    
    private init() {}
    
    private let defaultAdvancedPackRemote = URL(string: "https://recordio.app/models/advanced_diarization.pack")
    private let odrTag = "advanced_diarization_pack"
    private let odrResourceName = "advanced_diarization"
    private let odrResourceExtension = "pack"
    
    private var isAdvancedEnabled: Bool {
        return UserDefaults.standard.bool(forKey: "advancedDiarizationEnabled")
    }
    
    private func sanitizedURLString(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let trailingPunct = CharacterSet(charactersIn: ",`\"' ")
        return trimmed.trimmingCharacters(in: trailingPunct)
    }
    private var advancedPackURL: URL? {
        if let s = UserDefaults.standard.string(forKey: "advanced.diarization.url") {
            let sanitized = sanitizedURLString(s)
            if let u = URL(string: sanitized), let scheme = u.scheme, (scheme == "https" || scheme == "http"), u.host != nil {
                return u
            }
        }
        return defaultAdvancedPackRemote
    }
    private var advancedPackLocalURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Models/advanced_diarization.pack", isDirectory: false)
    }
    
    func isAdvancedPackInstalled() -> Bool {
        FileManager.default.fileExists(atPath: advancedPackLocalURL.path)
    }
    
    func processAudioFile(_ url: URL, completion: @escaping (Result<[SpeakerSegmentInfo], Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let segments: [SpeakerSegmentInfo]
                if self.isAdvancedEnabled, FileManager.default.fileExists(atPath: self.advancedPackLocalURL.path) {
                    segments = try self.analyzeSpeakersAdvanced(in: url)
                } else {
                    segments = try self.analyzeSpeakers(in: url)
                }
                DispatchQueue.main.async {
                    completion(.success(segments))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    func downloadAdvancedPack(completion: @escaping (Result<Void, Error>) -> Void) {
        #if os(iOS)
        let request = NSBundleResourceRequest(tags: Set([odrTag]))
        request.loadingPriority = NSBundleResourceRequestLoadingPriorityUrgent
        request.beginAccessingResources { error in
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let resourceURL = Bundle.main.url(forResource: self.odrResourceName, withExtension: self.odrResourceExtension) else {
                request.endAccessingResources()
                DispatchQueue.main.async { completion(.failure(SpeakerDiarizationError.processingFailed)) }
                return
            }
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let modelsDir = docs.appendingPathComponent("Models", isDirectory: true)
            try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
            let dest = self.advancedPackLocalURL
            do {
                if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
                try FileManager.default.copyItem(at: resourceURL, to: dest)
                request.endAccessingResources()
                DispatchQueue.main.async { completion(.success(())) }
            } catch {
                request.endAccessingResources()
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
        #else
        completion(.failure(SpeakerDiarizationError.processingFailed))
        #endif
    }
    
    private func analyzeSpeakers(in url: URL) throws -> [SpeakerSegmentInfo] {
        let asset = AVAsset(url: url)
        guard let audioTrack = asset.tracks(withMediaType: .audio).first else {
            throw SpeakerDiarizationError.noAudioTrack
        }
        
        let duration = CMTimeGetSeconds(asset.duration)
        
        let assetReader = try AVAssetReader(asset: asset)
        let trackOutput = try AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        
        assetReader.add(trackOutput)
        assetReader.startReading()
        
        var audioSamples: [Float] = []
        let segmentDuration: TimeInterval = 3.0
        var currentTime: TimeInterval = 0.0
        var segments: [SpeakerSegmentInfo] = []
        var currentSpeaker: Int = 0
        let numSpeakers = detectNumberOfSpeakers(audioTrack: audioTrack)
        
        while let sampleBuffer = trackOutput.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            
            var length: Int = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
            
            let sampleCount = length / MemoryLayout<Int16>.size
            var samples = [Float](repeating: 0, count: sampleCount)
            
            if let pointer = dataPointer {
                let int16Pointer = pointer.withMemoryRebound(to: Int16.self, capacity: sampleCount) { $0 }
                for i in 0..<sampleCount {
                    samples[i] = Float(Int16(bigEndian: int16Pointer[i])) / Float(Int16.max)
                }
            }
            
            audioSamples.append(contentsOf: samples)
            currentTime += Double(samples.count) / 48000.0
            
            if currentTime >= segmentDuration || currentTime >= duration {
                let segmentStart = currentTime - segmentDuration
                let segmentEnd = currentTime
                
                let speakerId = detectSpeaker(samples: audioSamples, numSpeakers: numSpeakers, currentSpeaker: &currentSpeaker)
                let confidence = calculateConfidence(samples: audioSamples)
                
                segments.append(SpeakerSegmentInfo(
                    speakerId: Int16(speakerId),
                    startTime: segmentStart,
                    endTime: segmentEnd,
                    confidence: confidence
                ))
                
                audioSamples = []
            }
        }
        
        assetReader.cancelReading()
        
        return mergeConsecutiveSegments(segments: segments, minSegmentDuration: 1.0)
    }
    
    private func analyzeSpeakersAdvanced(in url: URL) throws -> [SpeakerSegmentInfo] {
        let asset = AVAsset(url: url)
        guard let audioTrack = asset.tracks(withMediaType: .audio).first else {
            throw SpeakerDiarizationError.noAudioTrack
        }
        let reader = try AVAssetReader(asset: asset)
        let output = try AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        reader.add(output)
        reader.startReading()
        var frames: [[Float]] = []
        let windowSize = 1024
        var samples: [Float] = []
        while let sb = output.copyNextSampleBuffer() {
            guard let bb = CMSampleBufferGetDataBuffer(sb) else { break }
            var length: Int = 0
            var ptr: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(bb, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &ptr)
            if let p = ptr {
                let count = length / MemoryLayout<Int16>.size
                let int16p = p.withMemoryRebound(to: Int16.self, capacity: count) { $0 }
                for i in 0..<count {
                    samples.append(Float(int16p[i]) / Float(Int16.max))
                    if samples.count >= windowSize {
                        frames.append(computeFeatures(samples: Array(samples.suffix(windowSize))))
                        samples.removeAll(keepingCapacity: true)
                    }
                }
            }
        }
        reader.cancelReading()
        let k = max(2, detectNumberOfSpeakers(audioTrack: audioTrack))
        let assignments = kMeans(features: frames, k: k, iterations: 10)
        var result: [SpeakerSegmentInfo] = []
        let hopSeconds = Double(windowSize) / 48000.0
        var t = 0.0
        var lastSpeaker = assignments.first ?? 0
        var segStart = 0.0
        for (idx, spk) in assignments.enumerated() {
            if spk != lastSpeaker {
                let segEnd = segStart + Double(idx) * hopSeconds
                result.append(SpeakerSegmentInfo(speakerId: Int16(lastSpeaker), startTime: segStart, endTime: segEnd, confidence: 0.8))
                segStart = segEnd
                lastSpeaker = spk
            }
            t += hopSeconds
        }
        let finalEnd = segStart + Double(assignments.count) * hopSeconds
        result.append(SpeakerSegmentInfo(speakerId: Int16(lastSpeaker), startTime: segStart, endTime: finalEnd, confidence: 0.8))
        return mergeConsecutiveSegments(segments: result, minSegmentDuration: 0.5)
    }
    
    private func computeFeatures(samples: [Float]) -> [Float] {
        let n = samples.count
        guard n > 0 else { return [Float](repeating: 0, count: 13) }
        
        var windowed = samples
        var hann = [Float](repeating: 0, count: n)
        vDSP_hann_window(&hann, vDSP_Length(n), Int32(vDSP_HANN_DENORM))
        vDSP_vmul(samples, 1, hann, 1, &windowed, 1, vDSP_Length(n))
        
        var absSamples = [Float](repeating: 0, count: n)
        vDSP_vabs(windowed, 1, &absSamples, 1, vDSP_Length(n))
        
        var features = [Float](repeating: 0, count: 13)
        let step = max(1, n / 13)
        for i in 0..<13 {
            let start = i * step
            let end = min(n, start + step)
            if end > start {
                var sum: Float = 0
                vDSP_sve(Array(absSamples[start..<end]), 1, &sum, vDSP_Length(end - start))
                features[i] = sum / Float(end - start)
            } else {
                features[i] = 0
            }
        }
        return features
    }
    
    private func kMeans(features: [[Float]], k: Int, iterations: Int) -> [Int] {
        guard !features.isEmpty else { return [] }
        var centroids = Array(features.prefix(k))
        var assigns = [Int](repeating: 0, count: features.count)
        for _ in 0..<iterations {
            for (i, f) in features.enumerated() {
                var best = 0
                var bestDist = Float.greatestFiniteMagnitude
                for c in 0..<centroids.count {
                    let dist = euclidean(a: f, b: centroids[c])
                    if dist < bestDist { bestDist = dist; best = c }
                }
                assigns[i] = best
            }
            var sums = Array(repeating: [Float](repeating: 0, count: features[0].count), count: k)
            var counts = [Int](repeating: 0, count: k)
            for (i, f) in features.enumerated() {
                let a = assigns[i]
                for j in 0..<f.count { sums[a][j] += f[j] }
                counts[a] += 1
            }
            for c in 0..<k {
                if counts[c] > 0 {
                    centroids[c] = sums[c].map { $0 / Float(counts[c]) }
                }
            }
        }
        return assigns
    }
    
    private func euclidean(a: [Float], b: [Float]) -> Float {
        var s: Float = 0
        for i in 0..<min(a.count, b.count) {
            let d = a[i] - b[i]
            s += d * d
        }
        return s
    }
    
    private func detectNumberOfSpeakers(audioTrack: AVAssetTrack) -> Int {
        let formatDescriptions = audioTrack.formatDescriptions
        guard let formatDescription = formatDescriptions.first,
              let basicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription as! CMAudioFormatDescription) else {
            return 2
        }
        
        return Int(basicDescription.pointee.mChannelsPerFrame)
    }
    
    private func detectSpeaker(samples: [Float], numSpeakers: Int, currentSpeaker: inout Int) -> Int {
        guard !samples.isEmpty else { return currentSpeaker }
        
        var rms: Float = 0.0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        
        let spectralCentroid = calculateSpectralCentroid(samples: samples)
        let zcr = calculateZeroCrossingRate(samples: samples)
        
        let energyThreshold: Float = 0.01
        if rms < energyThreshold {
            return currentSpeaker
        }
        
        let speakerScore = abs(spectralCentroid - 2000.0) / 2000.0
        let speakerCandidate = Int(speakerScore * Double(numSpeakers)) % numSpeakers
        
        if Double.random(in: 0...1) < 0.7 {
            currentSpeaker = speakerCandidate
        } else if Double.random(in: 0...1) < 0.3 {
            currentSpeaker = Int.random(in: 0..<numSpeakers)
        }
        
        return currentSpeaker
    }
    
    private func calculateSpectralCentroid(samples: [Float]) -> Double {
        let frameSize = min(1024, samples.count)
        guard frameSize > 0 else { return 1000.0 }
        
        var weightedSum: Float = 0.0
        var magnitudeSum: Float = 0.0
        
        let startIndex = samples.count - frameSize
        for i in 0..<frameSize {
            let magnitude = abs(samples[startIndex + i])
            weightedSum += Float(i) * magnitude
            magnitudeSum += magnitude
        }
        
        let centroid = magnitudeSum > 0 ? Double(weightedSum / magnitudeSum) : 1000.0
        return centroid * 48000.0 / Double(frameSize)
    }
    
    private func calculateZeroCrossingRate(samples: [Float]) -> Float {
        guard samples.count > 1 else { return 0.0 }
        
        var crossings: Int = 0
        for i in 1..<samples.count {
            if samples[i] * samples[i - 1] < 0 {
                crossings += 1
            }
        }
        
        return Float(crossings) / Float(samples.count)
    }
    
    private func calculateConfidence(samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0.5 }
        
        var rms: Float = 0.0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        
        let signalStrength = min(1.0, rms * 10.0)
        let confidence = 0.7 + (signalStrength * 0.25)
        
        return Double(confidence)
    }
    
    private func mergeConsecutiveSegments(segments: [SpeakerSegmentInfo], minSegmentDuration: Double) -> [SpeakerSegmentInfo] {
        guard !segments.isEmpty else { return segments }
        
        var merged: [SpeakerSegmentInfo] = []
        var currentSegment = segments[0]
        
        for i in 1..<segments.count {
            let nextSegment = segments[i]
            
            if nextSegment.speakerId == currentSegment.speakerId &&
               nextSegment.startTime - currentSegment.endTime < 0.5 {
                currentSegment = SpeakerSegmentInfo(
                    speakerId: currentSegment.speakerId,
                    startTime: currentSegment.startTime,
                    endTime: nextSegment.endTime,
                    confidence: (currentSegment.confidence + nextSegment.confidence) / 2.0
                )
            } else {
                merged.append(currentSegment)
                currentSegment = nextSegment
            }
        }
        
        merged.append(currentSegment)
        
        return merged.filter { $0.endTime - $0.startTime >= minSegmentDuration }
    }
}

struct SpeakerSegmentInfo {
    let speakerId: Int16
    let startTime: Double
    let endTime: Double
    let confidence: Double
}

enum SpeakerDiarizationError: Error, LocalizedError {
    case noAudioTrack
    case processingFailed
    
    var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            return "No audio track found in file"
        case .processingFailed:
            return "Failed to process audio for speaker diarization"
        }
    }
}
