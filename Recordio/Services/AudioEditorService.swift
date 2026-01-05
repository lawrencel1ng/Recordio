import Foundation
import AVFoundation
import Accelerate

class AudioEditorService {
    static let shared = AudioEditorService()
    
    private init() {}
    
    enum EditOperation {
        case trim(startTime: TimeInterval, endTime: TimeInterval)
        case split(atTime: TimeInterval)
        case merge(recordings: [URL])
    }
    
    func trimAudio(from url: URL, startTime: TimeInterval, endTime: TimeInterval, outputURL: URL) throws {
        let asset = AVAsset(url: url)
        
        guard let audioTrack = asset.tracks(withMediaType: .audio).first else {
            throw AudioEditorError.noAudioTrack
        }
        
        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw AudioEditorError.compositionFailed
        }
        
        let startCMTime = CMTime(seconds: startTime, preferredTimescale: 1000)
        let endCMTime = CMTime(seconds: endTime, preferredTimescale: 1000)
        let duration = CMTimeSubtract(endCMTime, startCMTime)
        
        try compositionTrack.insertTimeRange(
            CMTimeRange(start: startCMTime, duration: duration),
            of: audioTrack,
            at: .zero
        )
        
        let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A)
        guard let exportSession = exportSession else {
            throw AudioEditorError.exportFailed
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = AVFileType.m4a
        
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
    }
    
    func splitAudio(from url: URL, atTime splitTime: TimeInterval) throws -> [URL] {
        let asset = AVAsset(url: url)
        let duration = CMTimeGetSeconds(asset.duration)
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let outputPath = documentsPath.appendingPathComponent("Edited", isDirectory: true)
        
        try FileManager.default.createDirectory(at: outputPath, withIntermediateDirectories: true)
        
        let part1URL = outputPath.appendingPathComponent("Part_1_\(UUID().uuidString).m4a")
        let part2URL = outputPath.appendingPathComponent("Part_2_\(UUID().uuidString).m4a")
        
        try trimAudio(from: url, startTime: 0, endTime: splitTime, outputURL: part1URL)
        try trimAudio(from: url, startTime: splitTime, endTime: duration, outputURL: part2URL)
        
        return [part1URL, part2URL]
    }
    
    func mergeAudio(recordings: [URL], outputURL: URL) throws {
        guard !recordings.isEmpty else {
            throw AudioEditorError.noAudioTrack
        }
        
        let composition = AVMutableComposition()
        var currentTime = CMTime.zero
        
        for (index, recordingURL) in recordings.enumerated() {
            let asset = AVAsset(url: recordingURL)
            
            guard let audioTrack = asset.tracks(withMediaType: .audio).first else {
                continue
            }
            
            guard let compositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw AudioEditorError.compositionFailed
            }
            
            let trackDuration = asset.duration
            try compositionTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: trackDuration),
                of: audioTrack,
                at: currentTime
            )
            
            currentTime = CMTimeAdd(currentTime, trackDuration)
        }
        
        let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A)
        guard let exportSession = exportSession else {
            throw AudioEditorError.exportFailed
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = AVFileType.m4a
        
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
    }
    
    func fadeIn(url: URL, duration: TimeInterval, outputURL: URL) throws {
        let asset = AVAsset(url: url)
        
        guard let audioTrack = asset.tracks(withMediaType: .audio).first else {
            throw AudioEditorError.noAudioTrack
        }
        
        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw AudioEditorError.compositionFailed
        }
        
        try compositionTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: asset.duration),
            of: audioTrack,
            at: .zero
        )
        
        let audioMix = AVMutableAudioMix()
        let audioMixInputParameters = AVMutableAudioMixInputParameters(track: compositionTrack)
        
        let fadeInDuration = CMTime(seconds: duration, preferredTimescale: 1000)
        audioMixInputParameters.setVolumeRamp(fromStartVolume: 0, toEndVolume: 1, timeRange: CMTimeRange(start: .zero, duration: fadeInDuration))
        
        audioMix.inputParameters = [audioMixInputParameters]
        
        let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A)
        exportSession?.audioMix = audioMix
        
        guard let exportSession = exportSession else {
            throw AudioEditorError.exportFailed
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = AVFileType.m4a
        
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
    }
    
    func fadeOut(url: URL, duration: TimeInterval, outputURL: URL) throws {
        let asset = AVAsset(url: url)
        let totalDuration = CMTimeGetSeconds(asset.duration)
        let fadeStartTime = totalDuration - duration
        
        guard let audioTrack = asset.tracks(withMediaType: .audio).first else {
            throw AudioEditorError.noAudioTrack
        }
        
        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw AudioEditorError.compositionFailed
        }
        
        try compositionTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: asset.duration),
            of: audioTrack,
            at: .zero
        )
        
        let audioMix = AVMutableAudioMix()
        let audioMixInputParameters = AVMutableAudioMixInputParameters(track: compositionTrack)
        
        let fadeOutStartTime = CMTime(seconds: fadeStartTime, preferredTimescale: 1000)
        let fadeOutDuration = CMTime(seconds: duration, preferredTimescale: 1000)
        
        audioMixInputParameters.setVolumeRamp(fromStartVolume: 1, toEndVolume: 0, timeRange: CMTimeRange(start: fadeOutStartTime, duration: fadeOutDuration))
        
        audioMix.inputParameters = [audioMixInputParameters]
        
        let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A)
        exportSession?.audioMix = audioMix
        
        guard let exportSession = exportSession else {
            throw AudioEditorError.exportFailed
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = AVFileType.m4a
        
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
    }
    
    func applyCrossfade(from url1: URL, to url2: URL, crossfadeDuration: TimeInterval, outputURL: URL) throws {
        let asset1 = AVAsset(url: url1)
        let asset2 = AVAsset(url: url2)
        
        guard let audioTrack1 = asset1.tracks(withMediaType: .audio).first,
              let audioTrack2 = asset2.tracks(withMediaType: .audio).first else {
            throw AudioEditorError.noAudioTrack
        }
        
        let composition = AVMutableComposition()
        
        guard let compositionTrack1 = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
              let compositionTrack2 = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw AudioEditorError.compositionFailed
        }
        
        let duration1 = CMTimeGetSeconds(asset1.duration)
        let crossfadeStartTime = duration1 - crossfadeDuration
        
        try compositionTrack1.insertTimeRange(
            CMTimeRange(start: .zero, duration: asset1.duration),
            of: audioTrack1,
            at: .zero
        )
        
        try compositionTrack2.insertTimeRange(
            CMTimeRange(start: .zero, duration: asset2.duration),
            of: audioTrack2,
            at: CMTime(seconds: crossfadeStartTime, preferredTimescale: 1000)
        )
        
        let audioMix = AVMutableAudioMix()
        
        let mixParams1 = AVMutableAudioMixInputParameters(track: compositionTrack1)
        let fadeOutStart = CMTime(seconds: crossfadeStartTime, preferredTimescale: 1000)
        let fadeOutDuration = CMTime(seconds: crossfadeDuration, preferredTimescale: 1000)
        mixParams1.setVolumeRamp(fromStartVolume: 1, toEndVolume: 0, timeRange: CMTimeRange(start: fadeOutStart, duration: fadeOutDuration))
        
        let mixParams2 = AVMutableAudioMixInputParameters(track: compositionTrack2)
        let fadeInStart = CMTime(seconds: crossfadeStartTime, preferredTimescale: 1000)
        mixParams2.setVolumeRamp(fromStartVolume: 0, toEndVolume: 1, timeRange: CMTimeRange(start: fadeInStart, duration: fadeOutDuration))
        
        audioMix.inputParameters = [mixParams1, mixParams2]
        
        let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A)
        exportSession?.audioMix = audioMix
        
        guard let exportSession = exportSession else {
            throw AudioEditorError.exportFailed
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = AVFileType.m4a
        
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
    }
}

enum AudioEditorError: Error, LocalizedError {
    case noAudioTrack
    case compositionFailed
    case exportFailed
    case invalidTimeRange
    case fileNotFound
    
    var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            return "No audio track found"
        case .compositionFailed:
            return "Failed to create audio composition"
        case .exportFailed:
            return "Failed to export audio"
        case .invalidTimeRange:
            return "Invalid time range specified"
        case .fileNotFound:
            return "Audio file not found"
        }
    }
}
