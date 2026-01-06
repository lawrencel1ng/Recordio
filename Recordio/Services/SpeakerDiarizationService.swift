import Foundation
import AVFoundation
import Accelerate
import CoreML

class SpeakerDiarizationService {
    static let shared = SpeakerDiarizationService()
    
    private var embeddingModel: MLModel?
    private var vadModel: MLModel?
    private var embeddingCache: [String: [[Float]]] = [:]
    private var timesCache: [String: [Double]] = [:]
    private var cacheOrder: [String] = []
    private let cacheCapacity: Int = 20
    private let storeKeyGlobal = "speaker_global_signatures"
    private let storeKeyNextId = "speaker_global_next_id"
    private let storeKeyRecMap = "speaker_recording_map"
    
    // MARK: - CoreML Model Integration
    
    func processAudioFile(_ url: URL, forceRefresh: Bool = false, progress: ((Double) -> Void)? = nil, completion: @escaping (Result<[SpeakerSegmentInfo], Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let segments = try self.analyzeSpeakers(in: url, forceRefresh: forceRefresh, progress: progress)
                DispatchQueue.main.async {
                    completion(.success(segments))
                }
            } catch {
                print("Diarization failed: \(error)")
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    // Removed legacy ODR/Download logic as models are now bundled directly.
    
    func ensureAdvancedPackInstalled() {
        // No-op: Models are bundled
    }
    
    private func analyzeSpeakers(in url: URL, forceRefresh: Bool = false, progress: ((Double) -> Void)? = nil) throws -> [SpeakerSegmentInfo] {
        print("🎯 [Diarization] Starting analysis for: \(url.lastPathComponent)")
        
        // Reset VAD state for fresh analysis
        resetVADState()
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("❌ [Diarization] File not found: \(url.path)")
            throw SpeakerDiarizationError.processingFailed
        }
        
        let asset = AVAsset(url: url)
        guard let audioTrack = asset.tracks(withMediaType: .audio).first else {
            print("❌ [Diarization] No audio track found")
            throw SpeakerDiarizationError.noAudioTrack
        }
        
        let duration = CMTimeGetSeconds(asset.duration)
        print("📊 [Diarization] Duration: \(String(format: "%.2f", duration))s")
        
        guard duration > 0 else {
            print("❌ [Diarization] Invalid duration")
            throw SpeakerDiarizationError.processingFailed
        }
        
        let assetReader = try AVAssetReader(asset: asset)
        let trackOutput = try AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        assetReader.add(trackOutput)
        assetReader.startReading()
        
        var frames: [[Float]] = []
        var times: [Double] = []
        
        // Check cache unless forceRefresh is requested
        if !forceRefresh, let cachedFrames = embeddingCache[url.path], let cachedTimes = timesCache[url.path], !cachedFrames.isEmpty {
            frames = cachedFrames
            times = cachedTimes
            print("📦 [Diarization] Using cached embeddings (\(frames.count) frames)")
        }
        
        let sampleRate: Double = 16000.0
        
        // WINDOW SIZING: CoreML SpeakerEmbedding model requires 160000 samples (10 seconds)
        // The model expects waveform input of shape (3 x 160000)
        let windowSeconds = 10.0  // 10 second window (model requirement)
        let minWindowSeconds = 2.0  // Minimum viable window for short recordings
        
        // Calculate adaptive window based on recording duration
        let effectiveWindowSeconds: Double
        if duration < windowSeconds {
            effectiveWindowSeconds = max(minWindowSeconds, duration * 0.8)
            print("📐 [Diarization] Short recording (\(String(format: "%.1f", duration))s) - using adaptive window")
        } else {
            effectiveWindowSeconds = windowSeconds
        }
        
        let windowSize = Int(sampleRate * effectiveWindowSeconds)
        // 50% overlap for good temporal resolution
        let hopSize = Int(sampleRate * effectiveWindowSeconds * 0.5)
        var buffer: [Float] = []
        var processedSamples: Int = 0
        
        let winSecs = Double(windowSize) / sampleRate
        let hopSecs = Double(hopSize) / sampleRate
        let overlapPct = (1.0 - hopSecs / winSecs) * 100
        print("🔧 [Diarization] Window: \(windowSize) samples (\(String(format: "%.1f", winSecs))s), Hop: \(hopSize) samples (\(String(format: "%.1f", hopSecs))s), Overlap: \(String(format: "%.0f", overlapPct))%")
        print("🤖 [Diarization] CoreML model available: \(embeddingModel != nil)")
        if forceRefresh { print("🔄 [Diarization] Force refresh requested, bypassing cache") }
        
        while let sampleBuffer = trackOutput.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            var length: Int = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
            let sampleCount = length / MemoryLayout<Int16>.size
            if let pointer = dataPointer {
                let int16Pointer = pointer.withMemoryRebound(to: Int16.self, capacity: sampleCount) { $0 }
                for i in 0..<sampleCount {
                    buffer.append(Float(int16Pointer[i]) / Float(Int16.max))
                    if buffer.count >= windowSize {
                        let frame = Array(buffer.prefix(windowSize))
                        let vadOn = voiceActivity(frame: frame, sampleRate: sampleRate)
                        if vadOn {
                            // Use CoreML model for embedding if available
                            if let embedding = self.generateEmbedding(from: frame, sampleRate: sampleRate) {
                                // Model returns normalized embedding directly
                                frames.append(embedding)
                                print("✅ [Diarization] CoreML embedding generated (dim: \(embedding.count))")
                            } else {
                                // Fallback to MFCC features
                                print("⚠️ [Diarization] CoreML failed, falling back to MFCC")
                                let mfcc = self.computeMFCC(samples: frame, sampleRate: sampleRate, numCoeffs: 13)
                                let norm = self.l2Normalize(mfcc)
                                frames.append(norm)
                            }
                            times.append(Double(processedSamples) / sampleRate)
                        }
                        buffer.removeFirst(hopSize)
                        processedSamples += hopSize
                        if let progress = progress {
                            let t = Double(processedSamples) / sampleRate
                            let pct = min(1.0, max(0.0, t / duration))
                            DispatchQueue.main.async { progress(pct) }
                        }
                    }
                }
            }
        }
        assetReader.cancelReading()
        
        if !frames.isEmpty {
            embeddingCache[url.path] = frames
            timesCache[url.path] = times
            if let idx = cacheOrder.firstIndex(of: url.path) { cacheOrder.remove(at: idx) }
            cacheOrder.append(url.path)
            if cacheOrder.count > cacheCapacity {
                let evict = cacheOrder.removeFirst()
                embeddingCache.removeValue(forKey: evict)
                timesCache.removeValue(forKey: evict)
            }
        }
        
        print("📈 [Diarization] Extracted \(frames.count) voice frames")
        
        // Log to Firebase for remote debugging
        AppLogger.shared.logEvent("diarization_analysis", parameters: [
            "voice_frames": frames.count,
            "duration": duration,
            "window_size": windowSize,
            "file_name": url.lastPathComponent
        ])
        
        guard !frames.isEmpty else {
            print("⚠️ [Diarization] No voice detected, returning single segment")
            AppLogger.shared.logEvent("diarization_no_voice", parameters: [
                "duration": duration,
                "file_name": url.lastPathComponent
            ])
            return [SpeakerSegmentInfo(speakerId: 0, startTime: 0, endTime: duration, confidence: 0.5)]
        }
        
        let k = selectKBySilhouette(features: frames, kRange: 1...8)
        print("🔍 [Diarization] Estimated \(k) speaker(s)")
        
        if k <= 1 {
            print("✅ [Diarization] Single speaker detected")
            return [SpeakerSegmentInfo(speakerId: 0, startTime: 0, endTime: duration, confidence: 0.7)]
        }
        
        // ENSEMBLE CLUSTERING: Weighted voting from multiple algorithms
        let assignsCos = kMeansCosine(features: frames, k: k, iterations: 20)
        let scoreCos = silhouette(features: frames, assigns: assignsCos, k: k)
        let assignsEuc = kMeans(features: frames, k: k, iterations: 20)
        let scoreEuc = silhouette(features: frames, assigns: assignsEuc, k: k)
        let assignsAgg = agglomerativeCosine(features: frames, k: k)
        let scoreAgg = silhouette(features: frames, assigns: assignsAgg, k: k)
        
        // Normalize scores for weighted voting
        let totalScore = max(0.001, scoreCos + scoreEuc + scoreAgg)
        let weightCos = scoreCos / totalScore
        let weightEuc = scoreEuc / totalScore
        let weightAgg = scoreAgg / totalScore
        
        print("🎯 [Ensemble] Weights - Cosine: \(String(format: "%.2f", weightCos)), Euclidean: \(String(format: "%.2f", weightEuc)), Agglomerative: \(String(format: "%.2f", weightAgg))")
        
        // Weighted voting for final assignments
        var assigns = [Int](repeating: 0, count: frames.count)
        for i in 0..<frames.count {
            var votes = [Int: Float]()
            votes[assignsCos[i], default: 0] += weightCos
            votes[assignsEuc[i], default: 0] += weightEuc
            votes[assignsAgg[i], default: 0] += weightAgg
            assigns[i] = votes.max(by: { $0.value < $1.value })?.key ?? 0
        }
        
        let centroids = computeCentroids(features: frames, assigns: assigns, k: k)
        
        // OVERLAP DETECTION: Find frames where speaker is ambiguous
        let overlapThreshold: Float = 0.7
        var overlapFrames: Set<Int> = []
        for (i, feature) in frames.enumerated() {
            var similarities: [(cluster: Int, similarity: Float)] = []
            for c in 0..<centroids.count {
                let d = cosineDistance(feature, centroids[c])
                let s = max(0, 1.0 - d)
                similarities.append((c, s))
            }
            similarities.sort { $0.similarity > $1.similarity }
            if similarities.count >= 2 && 
               similarities[0].similarity > overlapThreshold && 
               similarities[1].similarity > overlapThreshold {
                overlapFrames.insert(i)
            }
        }
        if !overlapFrames.isEmpty {
            print("🔀 [Diarization] Detected \(overlapFrames.count) frames with potential speaker overlap")
        }
        
        let vLabels = viterbiLabels(features: frames, centroids: centroids, stay: 0.9)
        let smoothed = smoothAssignments(vLabels, window: 3)
        
        var mapped = smoothed
        if let recId = RecordingManager.shared.recordings.first(where: { $0.audioURL == url })?.id?.uuidString {
            let globalMap = matchCentroidsToGlobal(centroids: centroids)
            saveRecordingMap(recordingId: recId, map: globalMap)
            mapped = smoothed.map { globalMap.indices.contains($0) ? globalMap[$0] : $0 }
        }
        
        var segments: [SpeakerSegmentInfo] = []
        var current = mapped.first ?? 0
        var segStartTime = times.first ?? 0.0
        for i in 1..<mapped.count {
            if mapped[i] != current {
                let segEndTime = times[i]
                let conf = segmentConfidence(times: times, features: frames, centroids: centroids, label: assigns[i-1], start: segStartTime, end: segEndTime)
                segments.append(SpeakerSegmentInfo(speakerId: Int16(current), startTime: segStartTime, endTime: segEndTime, confidence: conf))
                segStartTime = segEndTime
                current = mapped[i]
            }
        }
        let lastEnd = min(times.last ?? duration, duration)
        let lastConf = segmentConfidence(times: times, features: frames, centroids: centroids, label: assigns.last ?? 0, start: segStartTime, end: lastEnd)
        segments.append(SpeakerSegmentInfo(speakerId: Int16(current), startTime: segStartTime, endTime: lastEnd, confidence: lastConf))
        
        let merged = mergeConsecutiveSegments(segments: segments, minSegmentDuration: 0.5)
        print("✅ [Diarization] Complete: \(merged.count) segments across \(k) speakers")
        
        return merged
    }

    

    
    private func scoreSegments(url: URL, segments: [SpeakerSegmentInfo]) -> Float {
        var speechTime: Double = 0
        var totalTime: Double = 0
        let asset = AVAsset(url: url)
        totalTime = CMTimeGetSeconds(asset.duration)
        
        let sr: Double = 16000.0
        let window = Int(sr * 0.032)
        let hop = max(1, window / 2)
        
        var coverage: Double = 0
        var evaluated: Double = 0
        
        let reader = try? AVAssetReader(asset: asset)
        let output = try? AVAssetReaderTrackOutput(track: asset.tracks(withMediaType: .audio).first!, outputSettings: [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: sr,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        if let reader = reader, let output = output {
            reader.add(output)
            reader.startReading()
            var buf: [Float] = []
            var t: Double = 0
            while let sb = output.copyNextSampleBuffer() {
                guard let bb = CMSampleBufferGetDataBuffer(sb) else { break }
                var length: Int = 0
                var ptr: UnsafeMutablePointer<Int8>?
                CMBlockBufferGetDataPointer(bb, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &ptr)
                if let p = ptr {
                    let count = length / MemoryLayout<Int16>.size
                    let int16p = p.withMemoryRebound(to: Int16.self, capacity: count) { $0 }
                    for i in 0..<count {
                        buf.append(Float(int16p[i]) / Float(Int16.max))
                        if buf.count >= window {
                            let frame = Array(buf.prefix(window))
                            let vad = voiceActivity(frame: frame, sampleRate: sr)
                            let inSeg = segments.contains { seg in t >= seg.startTime && t < seg.endTime }
                            if vad { speechTime += Double(hop) / sr }
                            if vad && inSeg { coverage += Double(hop) / sr }
                            evaluated += Double(hop) / sr
                            buf.removeFirst(hop)
                            t += Double(hop) / sr
                        }
                    }
                }
            }
            reader.cancelReading()
        }
        
        let coverageRatio = totalTime > 0 ? coverage / max(evaluated, 1e-3) : 0
        let avgDur = segments.isEmpty ? 0 : segments.map { $0.endTime - $0.startTime }.reduce(0, +) / Double(segments.count)
        let flipCount = max(0, segments.count - 1)
        let flipPenalty = min(1.0, Double(flipCount) / max(1.0, totalTime / 2.0))
        let durScore = min(1.0, avgDur / 2.5)
        let score = Float(0.6 * coverageRatio + 0.3 * durScore - 0.1 * flipPenalty)
        return score
    }
    
    private func voiceActivity(frame: [Float], sampleRate: Double) -> Bool {
        if let v = coreMLVAD(frame: frame, sampleRate: sampleRate) {
            return v
        }
        return heuristicVAD(frame: frame)
    }
    
    // ADAPTIVE VAD: Much more permissive to ensure voice is detected
    private var noiseFloorEstimate: Float = 0.01
    private var noiseFloorFrameCount: Int = 0
    private let noiseFloorCalibrationFrames: Int = 5
    
    private func heuristicVAD(frame: [Float]) -> Bool {
        var rms: Float = 0
        vDSP_rmsqv(frame, 1, &rms, vDSP_Length(frame.count))
        var zcr: Float = 0
        for i in 1..<frame.count { if frame[i] * frame[i - 1] < 0 { zcr += 1 } }
        zcr /= Float(frame.count)
        
        // Adaptive noise floor estimation from initial frames (very conservative)
        if noiseFloorFrameCount < noiseFloorCalibrationFrames {
            noiseFloorEstimate = min(noiseFloorEstimate, rms * 0.5)  // Take minimum, not average
            noiseFloorFrameCount += 1
            
            // Log final calibration to Firebase
            if noiseFloorFrameCount == noiseFloorCalibrationFrames {
                AppLogger.shared.logEvent("vad_calibration", parameters: [
                    "noise_floor": Double(noiseFloorEstimate),
                    "last_rms": Double(rms),
                    "last_zcr": Double(zcr)
                ])
            }
        }
        
        // VERY permissive thresholds - only reject very quiet frames
        let energyThresh: Float = max(0.003, noiseFloorEstimate * 1.5)  // Much lower threshold
        
        // Voice activity: just needs to be above noise floor
        // Remove ZCR lower bound (was causing issues), only keep upper bound for pure noise
        let isVoice = rms > energyThresh && zcr < 0.4
        return isVoice
    }
    
    /// Reset VAD state for new recording analysis
    private func resetVADState() {
        noiseFloorEstimate = 0.01
        noiseFloorFrameCount = 0
    }
    
    // CoreML VAD is currently disabled in favor of the more robust Heuristic VAD
    private func coreMLVAD(frame: [Float], sampleRate: Double) -> Bool? {
        // Return nil to force fallback to heuristic VAD
        return nil
        
        /* DISABLED: CoreML model was rejecting valid speech frames
        guard let model = vadModel else { return nil }
        // ... (original implementation kept commented out for reference)
        */
    }
    
    private func computeMFCC(samples: [Float], sampleRate: Double, numCoeffs: Int) -> [Float] {
        let n = samples.count
        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_DENORM))
        var win = [Float](repeating: 0, count: n)
        vDSP_vmul(samples, 1, window, 1, &win, 1, vDSP_Length(n))
        
        let log2n = vDSP_Length(round(log2(Float(n))))
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(FFT_RADIX2)) else {
            return [Float](repeating: 0, count: numCoeffs)
        }
        var real = [Float](win)
        var imag = [Float](repeating: 0, count: n)
        var split = DSPSplitComplex(realp: &real, imagp: &imag)
        vDSP_fft_zip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
        var mags = [Float](repeating: 0, count: n/2)
        vDSP_zvmags(&split, 1, &mags, 1, vDSP_Length(n/2))
        vDSP_destroy_fftsetup(fftSetup)
        
        let numFilters = 16  // Must be power of 2 for DCT
        let melMin = 0.0
        let melMax = hzToMel(sampleRate/2.0)
        let melPoints = (0...numFilters+1).map { melMin + (melMax - melMin) * Double($0) / Double(numFilters+1) }
        let hzPoints = melPoints.map { melToHz($0) }
        let binPoints = hzPoints.map { Int(round(Double(n/2) * $0 / (sampleRate/2.0))) }
        
        var filterEnergies = [Float](repeating: 0, count: numFilters)
        for m in 1...numFilters {
            let f_m_minus = binPoints[m-1]
            let f_m = binPoints[m]
            let f_m_plus = binPoints[m+1]
            var energy: Float = 0
            if f_m_minus < f_m && f_m < f_m_plus {
                for k in f_m_minus..<f_m {
                    let w = Float(k - f_m_minus) / Float(max(1, f_m - f_m_minus))
                    energy += w * mags[min(k, mags.count-1)]
                }
                for k in f_m..<f_m_plus {
                    let w = Float(f_m_plus - k) / Float(max(1, f_m_plus - f_m))
                    energy += w * mags[min(k, mags.count-1)]
                }
            }
            filterEnergies[m-1] = max(1e-8, energy)
        }
        var logE = filterEnergies.map { logf($0) }
        let dctN = vDSP_Length(numFilters)
        var dctResult = [Float](repeating: 0, count: numCoeffs)
        
        // Create DCT setup - can return nil
        guard let dctSetup = vDSP_DCT_CreateSetup(nil, dctN, vDSP_DCT_Type.II) else {
            print("⚠️ Failed to create DCT setup, returning zeros")
            return dctResult
        }
        
        vDSP_DCT_Execute(dctSetup, logE, &dctResult)
        return Array(dctResult.prefix(numCoeffs))
    }
    
    private func hzToMel(_ hz: Double) -> Double { 2595.0 * log10(1.0 + hz / 700.0) }
    private func melToHz(_ mel: Double) -> Double { 700.0 * (pow(10.0, mel / 2595.0) - 1.0) }
    
    private func l2Normalize(_ v: [Float]) -> [Float] {
        var s: Float = 0
        vDSP_svesq(v, 1, &s, vDSP_Length(v.count))
        let n = sqrtf(max(s, 1e-8))
        var out = [Float](repeating: 0, count: v.count)
        vDSP_vsdiv(v, 1, [n], &out, 1, vDSP_Length(v.count))
        return out
    }
    
    private func selectKBySilhouette(features: [[Float]], kRange: ClosedRange<Int>) -> Int {
        var bestK = 1
        var bestScore: Float = -1.0 // Start with -1.0
        
        // Debug scores
        print("📊 [Clustering] Searching for optimal k within \(kRange)")
        
        // Cannot find more clusters than data points
        let maxK = min(kRange.upperBound, features.count)
        let effectiveRange = kRange.lowerBound...maxK
        
        for k in effectiveRange {
            if k == 1 {
                // k=1 is the baseline; if no other k has positive score, we fall back to 1
                continue
            }
            
            let assigns = kMeansCosine(features: features, k: k, iterations: 15)
            let score = silhouette(features: features, assigns: assigns, k: k)
            print("📊 [Clustering] k=\(k), score=\(String(format: "%.4f", score))")
            
            if score > bestScore {
                bestScore = score
                bestK = k
            }
        }
        
        // Threshold: if even best score is very low, prefer k=1
        if bestScore < 0.1 {
            print("📊 [Clustering] Best score \(String(format: "%.4f", bestScore)) < 0.1, defaulting to k=1")
            return 1
        }
        
        return bestK
    }
    
    private func silhouette(features: [[Float]], assigns: [Int], k: Int) -> Float {
        guard !features.isEmpty && k >= 2 else { return 0 }
        var clusters: [[Int]] = Array(repeating: [], count: k)
        for (i, a) in assigns.enumerated() { if a < k { clusters[a].append(i) } }
        var score: Float = 0
        var count: Int = 0
        for (i, xi) in features.enumerated() {
            let ci = assigns[i]
            let a = averageDistance(i, xi, features, clusters[ci])
            var b = Float.greatestFiniteMagnitude
            for c in 0..<k where c != ci && !clusters[c].isEmpty {
                let d = averageDistance(i, xi, features, clusters[c])
                if d < b { b = d }
            }
            if b.isFinite {
                let s = (b - a) / max(a, b)
                score += s
                count += 1
            }
        }
        return count > 0 ? score / Float(count) : 0
    }
    
    private func averageDistance(_ i: Int, _ xi: [Float], _ features: [[Float]], _ idxs: [Int]) -> Float {
        guard !idxs.isEmpty else { return 0 }
        var sum: Float = 0
        var c: Int = 0
        for j in idxs where j != i {
            sum += cosineDistance(xi, features[j])
            c += 1
        }
        return c > 0 ? sum / Float(c) : 0
    }
    
    private func cosineDistance(_ a: [Float], _ b: [Float]) -> Float {
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in 0..<min(a.count, b.count) {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        let denom = sqrtf(max(na, 1e-8)) * sqrtf(max(nb, 1e-8))
        return 1.0 - (dot / denom)
    }
    
    private func kMeansCosine(features: [[Float]], k: Int, iterations: Int) -> [Int] {
        guard !features.isEmpty else { return [] }
        var centroids = Array(features.prefix(k))
        var assigns = [Int](repeating: 0, count: features.count)
        for _ in 0..<iterations {
            for (i, f) in features.enumerated() {
                var best = 0
                var bestDist = Float.greatestFiniteMagnitude
                for c in 0..<centroids.count {
                    let dist = cosineDistance(f, centroids[c])
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
    
    private func agglomerativeCosine(features: [[Float]], k: Int) -> [Int] {
        let n = features.count
        if n == 0 { return [] }
        if k <= 1 { return [Int](repeating: 0, count: n) }
        var clusters: [[Int]] = (0..<n).map { [$0] }
        var centroids: [[Float]] = features
        func centroid(of idxs: [Int]) -> [Float] {
            var c = [Float](repeating: 0, count: features[0].count)
            var count = 0
            for i in idxs {
                let f = features[i]
                for j in 0..<f.count { c[j] += f[j] }
                count += 1
            }
            if count > 0 {
                for j in 0..<c.count { c[j] /= Float(count) }
            }
            return c
        }
        while clusters.count > k {
            var bestI = 0, bestJ = 1
            var bestDist = Float.greatestFiniteMagnitude
            for i in 0..<clusters.count {
                for j in (i+1)..<clusters.count {
                    let di = centroids[i]
                    let dj = centroids[j]
                    let d = cosineDistance(di, dj)
                    if d < bestDist {
                        bestDist = d
                        bestI = i
                        bestJ = j
                    }
                }
            }
            let merged = clusters[bestI] + clusters[bestJ]
            clusters[bestI] = merged
            centroids[bestI] = centroid(of: merged)
            clusters.remove(at: bestJ)
            centroids.remove(at: bestJ)
        }
        var assigns = [Int](repeating: 0, count: n)
        for (cIdx, members) in clusters.enumerated() {
            for i in members { assigns[i] = cIdx }
        }
        return assigns
    }
    
    private func computeCentroids(features: [[Float]], assigns: [Int], k: Int) -> [[Float]] {
        guard !features.isEmpty else { return [] }
        var sums = Array(repeating: [Float](repeating: 0, count: features[0].count), count: k)
        var counts = [Int](repeating: 0, count: k)
        for (i, f) in features.enumerated() {
            let a = min(max(assigns[i], 0), k - 1)
            for j in 0..<f.count { sums[a][j] += f[j] }
            counts[a] += 1
        }
        var centroids = sums
        for c in 0..<k {
            if counts[c] > 0 {
                centroids[c] = sums[c].map { $0 / Float(counts[c]) }
            }
        }
        return centroids
    }
    
    // IMPROVED CONFIDENCE SCORING: Incorporates duration, variance, and frame count
    private func segmentConfidence(times: [Double], features: [[Float]], centroids: [[Float]], label: Int, start: Double, end: Double) -> Double {
        guard !times.isEmpty, !features.isEmpty, label >= 0, label < centroids.count else { return 0.5 }
        let c = centroids[label]
        var sims: [Float] = []
        for (idx, t) in times.enumerated() {
            if t >= start && t < end {
                let d = cosineDistance(features[idx], c)
                let s = max(0, 1.0 - d)
                sims.append(s)
            }
        }
        if sims.isEmpty { return 0.5 }
        
        // Factor 1: Mean similarity to centroid
        var mean: Float = 0
        vDSP_meanv(sims, 1, &mean, vDSP_Length(sims.count))
        
        // Factor 2: Variance of similarities (lower is better - indicates consistency)
        var variance: Float = 0
        for s in sims {
            variance += (s - mean) * (s - mean)
        }
        variance /= Float(sims.count)
        let consistencyScore = 1.0 - min(1.0, Double(sqrt(variance)) * 2.0)
        
        // Factor 3: Segment duration (longer segments generally more reliable)
        let duration = end - start
        let durationScore = min(1.0, duration / 5.0)  // Max credit at 5 seconds
        
        // Factor 4: Frame count (more frames = more evidence)
        let frameCountScore = min(1.0, Double(sims.count) / 10.0)  // Max credit at 10 frames
        
        // Weighted combination
        let baseConf = Double(mean)
        let conf = 0.4 * baseConf + 0.25 * consistencyScore + 0.2 * durationScore + 0.15 * frameCountScore
        
        // Scale to 0.3-0.95 range (never fully certain, never zero)
        return 0.3 + 0.65 * min(1.0, max(0.0, conf))
    }
    
    private func loadGlobalSignatures() -> [Int: [Float]] {
        guard let data = UserDefaults.standard.data(forKey: storeKeyGlobal) else { return [:] }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: [Double]] else { return [:] }
        var out: [Int: [Float]] = [:]
        for (k, v) in obj {
            if let ki = Int(k) {
                out[ki] = v.map { Float($0) }
            }
        }
        return out
    }
    
    private func saveGlobalSignatures(_ dict: [Int: [Float]]) {
        var obj: [String: [Double]] = [:]
        for (k, v) in dict {
            obj["\(k)"] = v.map { Double($0) }
        }
        if let data = try? JSONSerialization.data(withJSONObject: obj) {
            UserDefaults.standard.set(data, forKey: storeKeyGlobal)
        }
    }
    
    private func nextGlobalId() -> Int {
        let n = UserDefaults.standard.integer(forKey: storeKeyNextId)
        let next = n + 1
        UserDefaults.standard.set(next, forKey: storeKeyNextId)
        return next
    }
    
    private func saveRecordingMap(recordingId: String, map: [Int]) {
        var all: [String: [Int]] = [:]
        if let data = UserDefaults.standard.data(forKey: storeKeyRecMap),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: [Int]] {
            all = obj
        }
        all[recordingId] = map
        if let data = try? JSONSerialization.data(withJSONObject: all) {
            UserDefaults.standard.set(data, forKey: storeKeyRecMap)
        }
    }
    
    // SPEAKER RE-IDENTIFICATION: Match centroids to global speaker signatures across recordings
    private func matchCentroidsToGlobal(centroids: [[Float]]) -> [Int] {
        var globals = loadGlobalSignatures()
        var mapping: [Int] = Array(repeating: 0, count: centroids.count)
        var usedGlobalIds: Set<Int> = []  // Prevent duplicate assignments
        
        print("🔍 [Speaker Re-ID] Matching \(centroids.count) speakers against \(globals.count) known signatures")
        
        // Sort by best match quality (greedy assignment)
        var matchCandidates: [(centroidIdx: Int, globalId: Int, similarity: Float)] = []
        
        for i in 0..<centroids.count {
            for (gid, sig) in globals {
                let d = cosineDistance(centroids[i], sig)
                let s = max(0, 1.0 - d)
                matchCandidates.append((i, gid, s))
            }
        }
        
        // Sort by similarity descending
        matchCandidates.sort { $0.similarity > $1.similarity }
        
        // Tiered thresholds for matching confidence
        let highConfidenceThreshold: Float = 0.90
        let mediumConfidenceThreshold: Float = 0.80
        let lowConfidenceThreshold: Float = 0.70
        
        var assignedCentroids: Set<Int> = []
        
        for candidate in matchCandidates {
            guard !assignedCentroids.contains(candidate.centroidIdx),
                  !usedGlobalIds.contains(candidate.globalId) else { continue }
            
            if candidate.similarity >= lowConfidenceThreshold {
                mapping[candidate.centroidIdx] = candidate.globalId
                usedGlobalIds.insert(candidate.globalId)
                assignedCentroids.insert(candidate.centroidIdx)
                
                // Update signature with momentum (high confidence = more weight to existing)
                let momentum: Float = candidate.similarity >= highConfidenceThreshold ? 0.8 : 
                                      candidate.similarity >= mediumConfidenceThreshold ? 0.6 : 0.4
                let oldSig = globals[candidate.globalId] ?? sigZero(len: centroids[candidate.centroidIdx].count)
                let updated = zip(oldSig, centroids[candidate.centroidIdx]).map { 
                    $0 * momentum + $1 * (1 - momentum) 
                }
                globals[candidate.globalId] = updated
                
                let confLevel = candidate.similarity >= highConfidenceThreshold ? "HIGH" :
                               candidate.similarity >= mediumConfidenceThreshold ? "MEDIUM" : "LOW"
                print("✅ [Speaker Re-ID] Matched centroid \(candidate.centroidIdx) → Speaker \(candidate.globalId) (\(confLevel) conf: \(String(format: "%.2f", candidate.similarity)))")
            }
        }
        
        // Create new speaker IDs for unmatched centroids
        for i in 0..<centroids.count {
            if !assignedCentroids.contains(i) {
                let newId = nextGlobalId()
                mapping[i] = newId
                globals[newId] = centroids[i]
                print("🆕 [Speaker Re-ID] New speaker detected → assigned ID \(newId)")
            }
        }
        
        saveGlobalSignatures(globals)
        return mapping
    }
    
    private func sigZero(len: Int) -> [Float] {
        return [Float](repeating: 0, count: len)
    }
    
    private func viterbiLabels(features: [[Float]], centroids: [[Float]], stay: Float) -> [Int] {
        let n = features.count
        let k = centroids.count
        if n == 0 || k == 0 { return [] }
        var emissions = Array(repeating: [Float](repeating: 0, count: k), count: n)
        for i in 0..<n {
            var sims = [Float](repeating: 0, count: k)
            var sum: Float = 0
            for s in 0..<k {
                let d = cosineDistance(features[i], centroids[s])
                let sim = max(0, 1.0 - d)
                sims[s] = sim
                sum += sim
            }
            if sum <= 1e-6 { sum = 1.0 }
            for s in 0..<k {
                let p = sims[s] / sum
                emissions[i][s] = log(max(p, 1e-6))
            }
        }
        let stayP = max(0.5, min(0.99, stay))
        let switchP = (1.0 - stayP) / Float(max(1, k - 1))
        let logStay = log(stayP)
        let logSwitch = log(switchP)
        var dp = [Float](repeating: 0, count: k)
        var back = Array(repeating: [Int](repeating: 0, count: k), count: n)
        for s in 0..<k { dp[s] = emissions[0][s] }
        if k > 1 {
            for i in 1..<n {
                var next = [Float](repeating: -Float.greatestFiniteMagnitude, count: k)
                for s in 0..<k {
                    var bestVal = -Float.greatestFiniteMagnitude
                    var bestPrev = 0
                    for ps in 0..<k {
                        let trans = (ps == s) ? logStay : logSwitch
                        let val = dp[ps] + trans + emissions[i][s]
                        if val > bestVal {
                            bestVal = val
                            bestPrev = ps
                        }
                    }
                    next[s] = bestVal
                    back[i][s] = bestPrev
                }
                dp = next
            }
        }
        var labels = [Int](repeating: 0, count: n)
        var bestLast = 0
        var bestVal = -Float.greatestFiniteMagnitude
        for s in 0..<k {
            if dp[s] > bestVal {
                bestVal = dp[s]
                bestLast = s
            }
        }
        labels[n - 1] = bestLast
        if n > 1 {
            for i in stride(from: n - 1, to: 0, by: -1) {
                labels[i - 1] = back[i][labels[i]]
            }
        }
        return labels
    }
    
    private func smoothAssignments(_ assigns: [Int], window: Int) -> [Int] {
        guard assigns.count > 1 else { return assigns }
        let w = max(1, window)
        var out = assigns
        let half = max(1, w / 2)
        for i in 0..<assigns.count {
            let start = max(0, i - half)
            let end = min(assigns.count - 1, i + half)
            var hist: [Int: Int] = [:]
            for j in start...end {
                hist[out[j], default: 0] += 1
            }
            var bestLabel = out[i]
            var bestCount = -1
            for (label, count) in hist {
                if count > bestCount || (count == bestCount && label == out[i]) {
                    bestCount = count
                    bestLabel = label
                }
            }
            out[i] = bestLabel
        }
        var i = 0
        let minRun = max(1, w / 2)
        while i < out.count {
            let current = out[i]
            var j = i + 1
            while j < out.count && out[j] == current { j += 1 }
            let runLen = j - i
            if runLen < minRun {
                let left = i > 0 ? out[i - 1] : current
                let right = j < out.count ? out[j] : current
                let replacement = left == right ? left : (runLen >= minRun ? current : right)
                for k in i..<j { out[k] = replacement }
            }
            i = j
        }
        return out
    }
    
    // Assuming this is part of a class/struct, add an initializer
    // If there's already an init, merge this call into it.
    // For this example, I'll assume it's a new init.
    private init() {
        loadEmbeddedModels()
    }
    
    func loadEmbeddedModels() {
        // Try multiple paths to find the models
        let candidates = [
            ("SpeakerEmbedding", "mlmodelc"),
            ("VAD", "mlmodelc")
        ]
        
        for (name, ext) in candidates {
            var modelURL: URL?
            
            // 1. Try default bundle resource (root)
            if let url = Bundle.main.url(forResource: name, withExtension: ext) {
                modelURL = url
            }
            // 2. Try Resources/Models subdirectory (common for folder references)
            else if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources/Models") {
                modelURL = url
            }
            // 3. Try Models subdirectory
            else if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Models") {
                modelURL = url
            }
            
            if let url = modelURL {
                do {
                    let model = try MLModel(contentsOf: url)
                    if name == "SpeakerEmbedding" { embeddingModel = model }
                    if name == "VAD" { vadModel = model }
                    print("✅ Loaded CoreML model: \(name) from \(url.path)")
                } catch {
                    print("❌ Failed to load CoreML model \(name): \(error)")
                }
            } else {
                print("⚠️ Could not find CoreML model file for \(name)")
            }
        }
    }
    
    private func generateEmbedding(from samples: [Float], sampleRate: Double) -> [Float]? {
        guard let model = embeddingModel else {
            print("⚠️ [CoreML] No embedding model loaded")
            return nil
        }
        
        let inputDescs = model.modelDescription.inputDescriptionsByName
        var waveformName = "waveform"
        var maskName: String?
        
        // SpeakerEmbedding model expects: waveform (3 x 160000), mask (3 x 589)
        // We must use 160000 samples for the waveform input
        let expectedSamples = 160000  // Hardcoded: model requirement
        let expectedChannels = 3
        
        // Verify waveform input exists
        if inputDescs[waveformName] == nil {
            // Try to find the waveform input by checking shapes
            for (name, desc) in inputDescs {
                if let constraint = desc.multiArrayConstraint {
                    if constraint.shape.count >= 2 {
                        let samples = Int(truncating: constraint.shape[1])
                        if samples == 160000 {
                            waveformName = name
                            print("🔍 [CoreML] Found waveform input: \(name)")
                            break
                        }
                    }
                }
            }
        }
        
        if inputDescs.keys.contains("mask") {
            maskName = "mask"
        }
        
        print("🎤 [CoreML] Input samples: \(samples.count), Expected: \(expectedSamples)")
        
        var audioSamples = samples
        if audioSamples.count < expectedSamples {
            audioSamples.append(contentsOf: [Float](repeating: 0, count: expectedSamples - audioSamples.count))
        } else if audioSamples.count > expectedSamples {
            audioSamples = Array(audioSamples.prefix(expectedSamples))
        }
        
        do {
            let multiArray = try MLMultiArray(shape: [NSNumber(value: expectedChannels), NSNumber(value: expectedSamples)], dataType: .float32)
            for i in 0..<expectedSamples {
                multiArray[[0, i] as [NSNumber]] = NSNumber(value: audioSamples[i])
            }
            let windowSize = 400
            var squared = [Float](repeating: 0, count: expectedSamples)
            vDSP_vsq(audioSamples, 1, &squared, 1, vDSP_Length(expectedSamples))
            var prefix = [Float](repeating: 0, count: expectedSamples + 1)
            var acc: Float = 0
            for i in 0..<expectedSamples {
                acc += squared[i]
                prefix[i + 1] = acc
            }
            for i in 0..<expectedSamples {
                let start = max(0, i - windowSize/2)
                let end = min(expectedSamples, i + windowSize/2)
                let sum = prefix[end] - prefix[start]
                let count = Float(max(1, end - start))
                let rms = sqrt(sum / count)
                if expectedChannels > 1 {
                    multiArray[[1, i] as [NSNumber]] = NSNumber(value: rms)
                }
            }
            for i in 0..<expectedSamples {
                let start = max(0, i - windowSize/2)
                let end = min(expectedSamples, i + windowSize/2)
                var weightedSum: Float = 0
                var magnitudeSum: Float = 0
                for j in start..<end {
                    let magnitude = abs(audioSamples[j])
                    weightedSum += Float(j - start) * magnitude
                    magnitudeSum += magnitude
                }
                let centroid = magnitudeSum > 0 ? weightedSum / magnitudeSum : 0
                if expectedChannels > 2 {
                    multiArray[[2, i] as [NSNumber]] = NSNumber(value: centroid / Float(windowSize))
                }
            }
            var inputDict: [String: MLFeatureValue] = [waveformName: MLFeatureValue(multiArray: multiArray)]
            if let maskName = maskName {
                // Mask has different shape: (3 x 589) - represents frames, not samples
                let maskLength = 589  // Model expects 589 frames in mask
                let mask = try MLMultiArray(shape: [NSNumber(value: expectedChannels), NSNumber(value: maskLength)], dataType: .float32)
                // Calculate how many samples per mask frame
                let samplesPerFrame = expectedSamples / maskLength
                let originalLength = samples.count
                for c in 0..<expectedChannels {
                    for i in 0..<maskLength {
                        // Frame is valid if corresponding samples exist
                        let sampleIndex = i * samplesPerFrame
                        let valid: Float = sampleIndex < originalLength ? 1.0 : 0.0
                        mask[[NSNumber(value: c), NSNumber(value: i)]] = NSNumber(value: valid)
                    }
                }
                inputDict[maskName] = MLFeatureValue(multiArray: mask)
            }
            let input = try MLDictionaryFeatureProvider(dictionary: inputDict)
            let output = try model.prediction(from: input)
            let outputDescriptions = model.modelDescription.outputDescriptionsByName
            guard let outputName = outputDescriptions.keys.first else {
                print("❌ [CoreML] No output descriptions")
                return nil
            }
            guard let outputFeature = output.featureValue(for: outputName)?.multiArrayValue else {
                print("❌ [CoreML] Could not get output feature")
                return nil
            }
            var embedding: [Float] = []
            let count = outputFeature.count
            for i in 0..<count {
                embedding.append(outputFeature[i].floatValue)
            }
            return embedding
        } catch {
            print("❌ [CoreML] Error: \(error.localizedDescription)")
            return nil
        }
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
    
    // Extract voice features for speaker distinction
    private func extractVoiceFeatures(samples: [Float]) -> [Float] {
        let n = samples.count
        guard n > 0 else { return [Float](repeating: 0, count: 6) }
        
        // Feature 1: RMS energy
        var rms: Float = 0.0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(n))
        
        // Feature 2: Zero crossing rate (voice pitch indicator)
        var zcr: Float = 0.0
        for i in 1..<n {
            if samples[i] * samples[i - 1] < 0 {
                zcr += 1
            }
        }
        zcr /= Float(n)
        
        // Feature 3-4: Spectral centroid and spread (voice timbre)
        var weightedSum: Float = 0.0
        var magnitudeSum: Float = 0.0
        for i in 0..<n {
            let magnitude = abs(samples[i])
            weightedSum += Float(i) * magnitude
            magnitudeSum += magnitude
        }
        let centroid = magnitudeSum > 0 ? weightedSum / magnitudeSum : Float(n) / 2
        let normalizedCentroid = centroid / Float(n)
        
        // Feature 5: Energy variance (speaking pattern)
        let chunkSize = max(1, n / 4)
        var chunkEnergies: [Float] = []
        for i in stride(from: 0, to: n, by: chunkSize) {
            let end = min(i + chunkSize, n)
            var chunkRms: Float = 0.0
            vDSP_rmsqv(Array(samples[i..<end]), 1, &chunkRms, vDSP_Length(end - i))
            chunkEnergies.append(chunkRms)
        }
        var energyVariance: Float = 0.0
        if !chunkEnergies.isEmpty {
            var mean: Float = 0
            vDSP_meanv(chunkEnergies, 1, &mean, vDSP_Length(chunkEnergies.count))
            for e in chunkEnergies {
                energyVariance += (e - mean) * (e - mean)
            }
            energyVariance /= Float(chunkEnergies.count)
        }
        
        // Feature 6: High-frequency content ratio (voice characteristic)
        let midPoint = n / 2
        var lowEnergy: Float = 0.0
        var highEnergy: Float = 0.0
        vDSP_rmsqv(Array(samples[0..<midPoint]), 1, &lowEnergy, vDSP_Length(midPoint))
        vDSP_rmsqv(Array(samples[midPoint..<n]), 1, &highEnergy, vDSP_Length(n - midPoint))
        let hfRatio = lowEnergy > 0 ? highEnergy / lowEnergy : 1.0
        
        return [rms * 10, zcr * 100, normalizedCentroid, sqrt(energyVariance) * 10, hfRatio, Float(n) / 48000.0]
    }
    
    // Estimate number of speakers from feature variance
    private func estimateSpeakerCount(frames: [[Float]]) -> Int {
        guard frames.count > 10 else { return 2 }  // Default to 2 for short recordings
        
        // Calculate feature variance across frames
        let numFeatures = frames[0].count
        var featureVariances: [Float] = []
        
        for f in 0..<numFeatures {
            var values = frames.map { $0[f] }
            var mean: Float = 0
            vDSP_meanv(values, 1, &mean, vDSP_Length(values.count))
            
            var variance: Float = 0
            for v in values {
                variance += (v - mean) * (v - mean)
            }
            variance /= Float(values.count)
            featureVariances.append(variance)
        }
        
        // High variance in ZCR and centroid suggests multiple speakers
        let zcrVariance = featureVariances.count > 1 ? featureVariances[1] : 0
        let centroidVariance = featureVariances.count > 2 ? featureVariances[2] : 0
        
        // Simple heuristic: if variance is high, likely multiple speakers
        let combinedVariance = zcrVariance + centroidVariance
        if combinedVariance > 50 {
            return min(4, max(2, Int(combinedVariance / 30) + 1))  // Cap at 4 speakers
        } else if combinedVariance > 10 {
            return 2
        }
        
        return 2  // Default to 2 speakers as most common case
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
