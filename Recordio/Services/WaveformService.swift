import Foundation
import AVFoundation
import Accelerate

class WaveformService {
    static let shared = WaveformService()
    
    private init() {}
    
    struct WaveformData {
        let samples: [Float]
        let duration: TimeInterval
        let sampleRate: Double
    }
    
    func generateWaveform(from url: URL, downsampleTo count: Int = 500) async throws -> [Float] {
        let asset = AVAsset(url: url)
        guard let audioTrack = asset.tracks(withMediaType: .audio).first else {
            throw WaveformError.noAudioTrack
        }
        
        let duration = CMTimeGetSeconds(asset.duration)
        
        let assetReader = try AVAssetReader(asset: asset)
        let trackOutput = try AVAssetReaderTrackOutput(
            track: audioTrack,
            outputSettings: [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        )
        
        assetReader.add(trackOutput)
        assetReader.startReading()
        
        var audioSamples: [Float] = []
        
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
        }
        
        assetReader.cancelReading()
        
        if audioSamples.isEmpty {
            return Array(repeating: 0.0, count: count)
        }
        
        return downsample(samples: audioSamples, to: count)
    }
    
    private func downsample(samples: [Float], to count: Int) -> [Float] {
        guard samples.count > count else {
            return samples
        }
        
        let stride = samples.count / count
        var downsampled: [Float] = []
        
        for i in 0..<count {
            let startIndex = i * stride
            let endIndex = min(startIndex + stride, samples.count)
            let chunk = Array(samples[startIndex..<endIndex])
            
            let rms = sqrt(chunk.map { $0 * $0 }.reduce(0, +) / Float(chunk.count))
            downsampled.append(rms)
        }
        
        return downsampled
    }
    
    func generateWaveformFromWAV(url: URL, downsampleTo count: Int = 500) throws -> [Float] {
        guard let data = try? Data(contentsOf: url) else {
            throw WaveformError.fileReadError
        }
        
        let samples = try parseWAVData(data)
        
        if samples.isEmpty {
            return Array(repeating: 0.0, count: count)
        }
        
        return downsample(samples: samples, to: count)
    }
    
    private func parseWAVData(_ data: Data) throws -> [Float] {
        let headerSize = 44
        
        guard data.count > headerSize else {
            throw WaveformError.invalidWAVFormat
        }
        
        let audioData = data.subdata(in: headerSize..<data.count)
        
        let sampleSize = 2
        let numberOfSamples = audioData.count / sampleSize
        
        var samples: [Float] = []
        samples.reserveCapacity(numberOfSamples)
        
        for i in 0..<numberOfSamples {
            let startIndex = i * sampleSize
            let sampleValue = audioData.subdata(in: startIndex..<startIndex + sampleSize).withUnsafeBytes { pointer in
                Int16(bigEndian: pointer.load(as: Int16.self))
            }
            
            let normalizedSample = Float(sampleValue) / Float(Int16.max)
            samples.append(normalizedSample)
        }
        
        return samples
    }
    
    func generateRealtimeWaveform(samples: [Float], downsampleTo count: Int = 100) -> [Float] {
        guard !samples.isEmpty else {
            return Array(repeating: 0.0, count: count)
        }
        
        return downsample(samples: samples, to: count)
    }
}

enum WaveformError: Error, LocalizedError {
    case noAudioTrack
    case fileReadError
    case invalidWAVFormat
    case processingFailed
    
    var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            return "No audio track found"
        case .fileReadError:
            return "Failed to read audio file"
        case .invalidWAVFormat:
            return "Invalid WAV file format"
        case .processingFailed:
            return "Failed to process waveform data"
        }
    }
}
