import Foundation
import UniformTypeIdentifiers
import AVFoundation

class ExportService {
    static let shared = ExportService()
    
    private init() {}
    
    func exportRecording(_ recording: Recording, format: ExportFormat, completion: @escaping (Result<URL, Error>) -> Void) {
        guard let audioURL = recording.audioURL else {
            completion(.failure(ExportError.noAudioFile))
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let outputURL = try self.exportAudio(from: audioURL, format: format, recording: recording)
                DispatchQueue.main.async {
                    completion(.success(outputURL))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    func exportTranscript(_ recording: Recording, format: TranscriptFormat, completion: @escaping (Result<URL, Error>) -> Void) {
        guard let transcript = recording.transcript else {
            completion(.failure(ExportError.noTranscript))
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let outputURL = try self.exportTranscriptText(transcript, format: format, recording: recording)
                DispatchQueue.main.async {
                    completion(.success(outputURL))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    private func exportAudio(from url: URL, format: ExportFormat, recording: Recording) throws -> URL {
        let outputURL = url.deletingPathExtension().appendingPathExtension(format.fileExtension)
        
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        
        switch format {
        case .wav:
            try FileManager.default.copyItem(at: url, to: outputURL)
        case .mp3:
            try convertToMP3(from: url, to: outputURL)
        case .m4a:
            try convertToM4A(from: url, to: outputURL)
        }
        
        return outputURL
    }
    
    private func exportTranscriptText(_ transcript: String, format: TranscriptFormat, recording: Recording) throws -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let outputURL = documentsPath.appendingPathComponent("\(recording.title).\(format.fileExtension)")
        
        var content = ""
        
        switch format {
        case .txt:
            content = transcript
        case .srt:
            content = convertToSRT(transcript: transcript, segments: recording.speakerSegmentsArray)
        case .json:
            content = convertToJSON(transcript: transcript, recording: recording)
        }
        
        try content.write(to: outputURL, atomically: true, encoding: .utf8)
        
        return outputURL
    }
    
    private func convertToMP3(from inputURL: URL, to outputURL: URL) throws {
        let asset = AVURLAsset(url: inputURL)
        let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality)
        
        guard let exportSession = exportSession else {
            throw ExportError.conversionFailed
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp3
        
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
    
    private func convertToM4A(from inputURL: URL, to outputURL: URL) throws {
        let asset = AVURLAsset(url: inputURL)
        let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A)
        
        guard let exportSession = exportSession else {
            throw ExportError.conversionFailed
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
    
    private func convertToSRT(transcript: String, segments: [SpeakerSegment]) -> String {
        var srtContent = ""
        let lines = transcript.components(separatedBy: "\n")
        
        for (index, segment) in segments.enumerated() {
            let startTime = formatSRTime(segment.startTime)
            let endTime = formatSRTime(segment.endTime)
            
            srtContent += "\(index + 1)\n"
            srtContent += "\(startTime) --> \(endTime)\n"
            srtContent += "Speaker \(segment.speakerId + 1)\n\n"
        }
        
        return srtContent
    }
    
    private func formatSRTime(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        let milliseconds = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, secs, milliseconds)
    }
    
    private func convertToJSON(transcript: String, recording: Recording) -> String {
        let data: [String: Any] = [
            "title": recording.title,
            "createdAt": ISO8601DateFormatter().string(from: recording.createdAt ?? Date()),
            "duration": recording.duration,
            "transcript": transcript,
            "speakers": recording.speakerSegmentsArray.map { segment in
                [
                    "id": segment.speakerId,
                    "startTime": segment.startTime,
                    "endTime": segment.endTime,
                    "confidence": segment.confidence
                ]
            }
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data, options: .prettyPrinted),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return "{}"
        }
        
        return jsonString
    }
}

enum ExportFormat: String, CaseIterable {
    case wav = "WAV"
    case mp3 = "MP3"
    case m4a = "M4A"
    
    var fileExtension: String {
        return rawValue.lowercased()
    }
    
    var utType: UTType? {
        switch self {
        case .wav: return UTType.wav
        case .mp3: return UTType("public.mp3")
        case .m4a: return UTType.mpeg4Audio
        }
    }
}

enum TranscriptFormat: String, CaseIterable {
    case txt = "TXT"
    case srt = "SRT"
    case json = "JSON"
    
    var fileExtension: String {
        return rawValue.lowercased()
    }
}

enum ExportError: Error, LocalizedError {
    case noAudioFile
    case noTranscript
    case conversionFailed
    
    var errorDescription: String? {
        switch self {
        case .noAudioFile:
            return "No audio file found"
        case .noTranscript:
            return "No transcript available"
        case .conversionFailed:
            return "Failed to convert file"
        }
    }
}
