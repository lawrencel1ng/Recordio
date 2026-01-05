import SwiftUI
import AVFoundation
import CoreMedia
import Combine
import CoreData

struct RecordingDetailView: View {
    let recording: Recording
    @StateObject private var audioPlayer = AudioPlayer()
    @StateObject private var recordingManager = RecordingManager.shared
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var showSpectrogram = false
    @State private var showingEditSheet = false
    @State private var showingUpgradePrompt = false
    @State private var showingExportSheet = false
    @State private var showingEditorSheet = false
    @State private var isProcessing = false
    @State private var processingAlert: ProcessingAlert?
    @State private var editorError: String?
    @State private var showingErrorAlert = false
    @State private var showingMoveSheet = false
    @State private var selectedMoveFolder: Folder?
    
    init(recording: Recording) {
        self.recording = recording
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                headerView
                audioPlayerView
                speakerTimelineView
                summaryView
                transcriptView
                actionsView
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: {
                        if let url = recording.audioURL {
                            shareItems = [url]
                            showingShareSheet = true
                        }
                    }) { Label("Share", systemImage: "square.and.arrow.up") }
                    
                    Button(action: { showingExportSheet = true }) { Label("Export", systemImage: "square.and.arrow.up.on.square") }
                    
                    Button(action: { showingEditorSheet = true }) { Label("Open Editor", systemImage: "scissors") }
                    
                    Button(action: duplicateRecording) { Label("Duplicate Recording", systemImage: "doc.on.doc") }
                    
                    Button(action: { showingMoveSheet = true }) { Label("Move to Folder", systemImage: "folder.badge.plus") }
                    
                    Button(action: toggleFavorite) { Label("Mark as Favorite", systemImage: "star") }
                    
                    Button(action: generateShareableLink) { Label("Generate Shareable Link", systemImage: "link") }
                    
                    if appState.canAccess(feature: .audioEnhancement) {
                        Button(action: enhanceAudio) { Label("Enhance Audio", systemImage: "wand.and.stars") }
                    }
                    if appState.canAccess(feature: .aiNoiseReduction) {
                        Button(action: reduceNoise) { Label("Reduce Noise", systemImage: "speaker.wave.3.fill") }
                    }
                    
                    Divider()
                    
                    Button(action: { showingEditSheet = true }) { Label("Edit Info", systemImage: "pencil") }
                    
                    Divider()
                    
                    Button(role: .destructive, action: {
                        RecordingManager.shared.deleteRecording(recording)
                        dismiss()
                    }) { Label("Delete", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingMoveSheet) {
            FolderSelectionSheet(recording: recording)
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(items: shareItems)
        }
        .sheet(isPresented: $showingEditSheet) {
            EditRecordingSheet(recording: recording)
        }
        .sheet(isPresented: $showingUpgradePrompt) {
            ProUpgradePrompt(trigger: .manualExport)
        }
        .sheet(isPresented: $showingExportSheet) {
            ExportOptionsSheet(recording: recording, isProcessing: $isProcessing)
        }
        .sheet(isPresented: $showingEditorSheet) {
            AudioEditorSheet(recording: recording, isProcessing: $isProcessing, error: $editorError, showError: $showingErrorAlert)
        }
        .alert(item: $processingAlert) { alert in
            Alert(
                title: Text(alert == .exporting ? "Exporting..." : "Processing..."),
                message: Text("Please wait while we process your recording."),
                dismissButton: nil
            )
        }
        .alert("Editor Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            if let error = editorError {
                Text(error)
            }
        }
        .onAppear {
            if let url = recording.audioURL {
                audioPlayer.load(url: url)
            }
        }
    }
    
    enum ProcessingAlert: Identifiable {
        case enhancing
        case reducingNoise
        case exporting
        
        var id: String {
            switch self {
            case .enhancing: return "enhancing"
            case .reducingNoise: return "reducingNoise"
            case .exporting: return "exporting"
            }
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 16) {
            Text(recording.title ?? "Untitled Recording")
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            HStack(spacing: 20) {
                Label(formatDuration(recording.duration), systemImage: "clock")
                Label(formatDate(recording.createdAt), systemImage: "calendar")
                Label(recording.audioQuality ?? "Standard", systemImage: "waveform")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            
            if appState.canAccess(feature: .speakerDiarization) && recording.detectedSpeakers > 0 {
                HStack(spacing: 8) {
                    ForEach(0..<recording.detectedSpeakers, id: \.self) { speakerId in
                        SpeakerBadge(speakerId: Int16(speakerId))
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }
    
    private var audioPlayerView: some View {
        VStack(spacing: 20) {
            if showSpectrogram {
                SpectrogramView(recording: recording)
                    .frame(height: 160)
            } else {
                WaveformVisualization(recording: recording)
            }
            
            HStack(spacing: 20) {
                Button(action: skipBackward) {
                    Image(systemName: "gobackward.15")
                        .font(.title2)
                }
                .accessibilityLabel("Skip Backward 15 Seconds")
                
                Button(action: togglePlayPause) {
                    Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                }
                .accessibilityLabel(audioPlayer.isPlaying ? "Pause" : "Play")
                
                Button(action: skipForward) {
                    Image(systemName: "goforward.15")
                        .font(.title2)
                }
                .accessibilityLabel("Skip Forward 15 Seconds")
            }
            
            Picker("View", selection: $showSpectrogram) {
                Text("Waveform").tag(false)
                Text("Spectrogram").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
            VStack(spacing: 4) {
                Slider(value: $audioPlayer.currentTime, in: 0...audioPlayer.duration)
                
                HStack {
                    Text(formatDuration(audioPlayer.currentTime))
                    Spacer()
                    Text(formatDuration(audioPlayer.duration))
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal)
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .padding(.vertical, 8)
    }
    
    private var speakerTimelineView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if appState.canAccess(feature: .speakerDiarization) {
                Text("Speaker Timeline")
                    .font(.headline)
                
                if recording.speakerSegmentsArray.isEmpty {
                    Text("Speaker analysis not available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    SpeakerTimeline(segments: recording.speakerSegmentsArray, duration: recording.duration)
                }
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .padding(.vertical, 8)
    }
    
    private var transcriptView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Transcript")
                    .font(.headline)
                
                Spacer()
                
                if !appState.canAccess(feature: .aiSummaries) {
                    Button(action: { showingUpgradePrompt = true }) {
                        Label("Upgrade for AI", systemImage: "crown.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
            
            if let transcript = recording.transcript, !transcript.isEmpty {
                Text(transcript)
                    .font(.body)
                    .lineSpacing(6)
            } else if appState.canAccess(feature: .aiSummaries) {
                Text("Transcription in progress...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Button(action: { showingUpgradePrompt = true }) {
                    VStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 40))
                            .foregroundColor(.orange)
                        
                        Text("Unlock AI Transcription")
                            .font(.headline)
                        
                        Text("Get automatic transcription with speaker labels")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)
                }
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .padding(.vertical, 8)
    }
    
    private var summaryView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AI Summary")
                    .font(.headline)
                
                Spacer()
                
                if appState.canAccess(feature: .aiSummaries) {
                    Menu {
                        Button("Executive", action: { generateSummary(type: .executive) })
                        Button("Detailed", action: { generateSummary(type: .detailed) })
                        Button("Bullet Points", action: { generateSummary(type: .bulletPoints) })
                        Button("Action Items", action: { generateSummary(type: .actionItems) })
                    } label: {
                        Label("Summary Type", systemImage: "list.bullet")
                            .font(.caption)
                    }
                }
            }
            
            if let summary = recording.aiSummary, !summary.isEmpty {
                Text(summary)
                    .font(.body)
                    .lineSpacing(4)
                
                if let actionItems = recording.actionItems, !actionItems.isEmpty {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Action Items", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundColor(.green)
                        
                        ForEach(actionItems.components(separatedBy: "|||"), id: \.self) { item in
                            HStack(alignment: .top, spacing: 8) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 6)
                                
                                Text(item)
                                    .font(.subheadline)
                            }
                        }
                    }
                }
                
                if let keyTopics = recording.keyTopics, !keyTopics.isEmpty {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Key Topics", systemImage: "tag.fill")
                            .font(.headline)
                            .foregroundColor(.blue)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(keyTopics.components(separatedBy: ", "), id: \.self) { topic in
                                    Text(topic)
                                        .font(.caption)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.blue.opacity(0.1))
                                        .foregroundColor(.blue)
                                        .cornerRadius(16)
                                }
                            }
                        }
                    }
                }
            } else if appState.canAccess(feature: .aiSummaries) {
                Button(action: { generateSummary(type: .executive) }) {
                    VStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 40))
                            .foregroundColor(.orange)
                        
                        Text("Generate AI Summary")
                            .font(.headline)
                        
                        Text("Get instant insights from your recording")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)
                }
            } else {
                Button(action: { showingUpgradePrompt = true }) {
                    VStack(spacing: 12) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.orange)
                        
                        Text("Upgrade for AI Summary")
                            .font(.headline)
                        
                        Text("Unlock powerful AI analysis of your recordings")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)
                }
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .padding(.vertical, 8)
    }
    
    private func generateSummary(type: SummaryService.SummaryType) {
        SummaryService.shared.updateRecordingSummary(recording, type: type)
    }
    
    private var actionsView: some View {
        VStack(spacing: 16) {
            // Analytics link
            NavigationLink {
                RecordingAnalyticsView(recording: recording)
            } label: {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: "chart.pie.fill")
                            .font(.title3)
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("View Analytics")
                            .font(.headline)
                        Text("Speaker stats, WPM, filler words")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            
            // Bookmarks section
            if let bookmarks = recording.bookmarks as? Set<Bookmark>, !bookmarks.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "bookmark.fill")
                            .foregroundColor(.orange)
                        Text("Bookmarks")
                            .font(.headline)
                    }
                    
                    ForEach(Array(bookmarks.sorted { $0.timestamp < $1.timestamp }), id: \.id) { bookmark in
                        HStack {
                            Text(formatTimestamp(bookmark.timestamp))
                                .font(.caption)
                                .foregroundColor(.blue)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                            
                            Text(bookmark.label ?? "Bookmark")
                                .font(.subheadline)
                            
                            Spacer()
                            
                            Button(action: { jumpToBookmark(bookmark) }) {
                                Image(systemName: "play.fill")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
            }
            
            // Action buttons
            VStack(spacing: 12) {
                Button(action: { showingEditorSheet = true }) {
                    Label("Edit Recording", systemImage: "scissors")
                }
                .disabled(isProcessing)
                
                Button(action: enhanceAudio) {
                    Label("Enhance Audio", systemImage: "wand.and.stars")
                }
                .disabled(!appState.canAccess(feature: .audioEnhancement) || isProcessing)
                
                Button(action: reduceNoise) {
                    Label("Reduce Noise", systemImage: "speaker.wave.3.fill")
                }
                .disabled(!appState.canAccess(feature: .aiNoiseReduction) || isProcessing)
                
                Button(action: showExportOptions) {
                    Label("Export Recording", systemImage: "square.and.arrow.up")
                }
                .disabled(isProcessing)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .padding(.vertical, 8)
    }
    
    private func jumpToBookmark(_ bookmark: Bookmark) {
        audioPlayer.seek(to: bookmark.timestamp)
    }
    
    private func formatTimestamp(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    private func togglePlayPause() {
        if audioPlayer.isPlaying {
            audioPlayer.pause()
        } else {
            if let url = recording.audioURL {
                if audioPlayer.currentTime == 0 && audioPlayer.duration == 0 {
                    audioPlayer.play(url: url)
                } else {
                    audioPlayer.resume()
                }
            }
        }
    }
    
    private func skipBackward() {
        audioPlayer.seek(to: max(0, audioPlayer.currentTime - 15))
    }
    
    private func skipForward() {
        audioPlayer.seek(to: min(audioPlayer.duration, audioPlayer.currentTime + 15))
    }
    
    private func enhanceAudio() {
        guard let url = recording.audioURL else {
            showProcessingError("No audio file found")
            return
        }
        isProcessing = true
        processingAlert = .enhancing
        
        AudioProcessor.shared.enhanceAudio(url: url) { [self] result in
            isProcessing = false
            processingAlert = nil
            
            switch result {
            case .success(let outputURL):
                // Show share sheet with enhanced audio
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showShareSheet(for: outputURL, title: "Enhanced Audio")
                }
            case .failure(let error):
                showProcessingError(error.localizedDescription)
            }
        }
    }
    
    private func reduceNoise() {
        guard let url = recording.audioURL else {
            showProcessingError("No audio file found")
            return
        }
        isProcessing = true
        processingAlert = .reducingNoise
        
        AudioProcessor.shared.reduceNoise(url: url) { [self] result in
            isProcessing = false
            processingAlert = nil
            
            switch result {
            case .success(let outputURL):
                // Show share sheet with denoised audio
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showShareSheet(for: outputURL, title: "Denoised Audio")
                }
            case .failure(let error):
                showProcessingError(error.localizedDescription)
            }
        }
    }
    
    private func duplicateRecording() {
        _ = recordingManager.duplicateRecording(recording)
    }
    
    private func toggleFavorite() {
        recordingManager.toggleFavorite(recording)
    }
    
    private func generateShareableLink() {
        if let url = recording.audioURL {
            shareItems = [url]
            showingShareSheet = true
        }
    }
    
    private func showShareSheet(for url: URL, title: String) {
        shareItems = [url]
        showingShareSheet = true
    }
    
    private func showProcessingError(_ message: String) {
        DispatchQueue.main.async {
            // Could add an @State alert for errors
            print("Processing error: \(message)")
        }
    }
    
    private func showExportOptions() {
        showingExportSheet = true
    }
    
    private func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#if canImport(AVFoundation)
import AVFoundation
struct SpectrogramView: View {
    let recording: Recording
    @State private var magnitudes: [[CGFloat]] = []
    
    var body: some View {
        GeometryReader { geo in
            if magnitudes.isEmpty {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.1))
                    ProgressView()
                }
            } else {
                let timeCount = magnitudes.count
                let freqCount = magnitudes.first?.count ?? 0
                HStack(spacing: 0) {
                    ForEach(0..<timeCount, id: \.self) { t in
                        VStack(spacing: 0) {
                            ForEach(0..<freqCount, id: \.self) { f in
                                Rectangle()
                                    .fill(color(for: magnitudes[t][f]))
                            }
                        }
                    }
                }
                .onAppear {
                    let w = max(1, Int(geo.size.width / CGFloat(max(1, timeCount))))
                    let h = max(1, Int(geo.size.height / CGFloat(max(1, freqCount))))
                    _ = w; _ = h
                }
            }
        }
        .onAppear { generateSpectrogram() }
    }
    
    private func color(for value: CGFloat) -> Color {
        let v = min(1, max(0, value))
        return Color(hue: 0.6 - 0.6 * v, saturation: 1, brightness: max(0.2, v))
    }
    
    private func generateSpectrogram() {
        guard let url = recording.audioURL else { return }
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .audio).first else { return }
        let reader = try? AVAssetReader(asset: asset)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]
        let output = AVAssetReaderAudioMixOutput(audioTracks: [track], audioSettings: settings)
        output.audioMix = AVAudioMix()
        if let reader = reader, reader.canAdd(output) {
            reader.add(output)
            reader.startReading()
            var samples: [Float] = []
            while reader.status == .reading {
                if let buf = output.copyNextSampleBuffer(),
                   let block = CMSampleBufferGetDataBuffer(buf) {
                    let length = CMBlockBufferGetDataLength(block)
                    var buffer = [UInt8](repeating: 0, count: length)
                    let status = buffer.withUnsafeMutableBytes { ptr in
                        CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: ptr.baseAddress!)
                    }
                    guard status == kCMBlockBufferNoErr else { continue }
                    let count = length / MemoryLayout<Int16>.size
                    samples.reserveCapacity(samples.count + count)
                    buffer.withUnsafeBytes { raw in
                        let ptr = raw.bindMemory(to: Int16.self)
                        for i in 0..<count {
                            samples.append(Float(ptr[i]) / Float(Int16.max))
                        }
                    }
                } else {
                    break
                }
            }
            let windowSize = 1024
            let hopSize = 512
            let bins = 64
            var result: [[CGFloat]] = []
            var i = 0
            while i + windowSize <= samples.count {
                let window = Array(samples[i..<(i+windowSize)])
                var re = [Float](repeating: 0, count: windowSize)
                var im = [Float](repeating: 0, count: windowSize)
                for k in 0..<windowSize { re[k] = window[k] }
                var magn = [CGFloat](repeating: 0, count: bins)
                let step = windowSize / (bins * 2)
                for b in 0..<bins {
                    var sum: Float = 0
                    let start = b * step
                    let end = min(windowSize/2 - 1, start + step)
                    for k in start..<end {
                        let v = re[k]*re[k] + im[k]*im[k]
                        sum += v
                    }
                    magn[b] = CGFloat(min(1.0, sqrt(sum)))
                }
                result.append(magn)
                i += hopSize
            }
            DispatchQueue.main.async {
                magnitudes = result
            }
        }
    }
}
#endif
struct WaveformVisualization: View {
    let recording: Recording
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<50, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(waveformColor(for: index))
                        .frame(width: 4, height: barHeight(for: index))
                }
            }
            .frame(height: 80)
            
            if appState.canAccess(feature: .speakerDiarization) && recording.detectedSpeakers > 0 {
                HStack(spacing: 4) {
                    ForEach(0..<recording.detectedSpeakers, id: \.self) { speakerId in
                        Circle()
                            .fill(speakerColor(speakerId: Int16(speakerId)))
                            .frame(width: 12, height: 12)
                    }
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
        }
    }
    
    private func waveformColor(for index: Int) -> Color {
        return Color.blue.opacity(0.6)
    }
    
    private func barHeight(for index: Int) -> CGFloat {
        let normalizedPosition = Double(index) / 50.0
        let baseHeight = sin(normalizedPosition * .pi * 2) * 0.5 + 0.5
        return 20 + baseHeight * 40
    }
    
    private func speakerColor(speakerId: Int16) -> Color {
        let colors = ["#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4", "#FFEAA7"]
        let hex = colors[Int(speakerId) % colors.count]
        return Color(hex: hex) ?? .blue
    }
}

struct SpeakerTimeline: View {
    let segments: [SpeakerSegment]
    let duration: Double
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 1) {
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                    let width = (segment.endTime - segment.startTime) / duration * geometry.size.width
                    Rectangle()
                        .fill(speakerColor(for: segment.speakerId))
                        .frame(width: max(2, width))
                }
            }
        }
        .frame(height: 30)
        .cornerRadius(6)
    }
    
    private func speakerColor(for speakerId: Int16) -> Color {
        let colors = ["#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4", "#FFEAA7"]
        let hex = colors[Int(speakerId) % colors.count]
        return Color(hex: hex) ?? .blue
    }
}

struct SpeakerBadge: View {
    let speakerId: Int16
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(speakerColor)
                .frame(width: 8, height: 8)
            
            Text("Speaker \(speakerId + 1)")
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(speakerColor.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var speakerColor: Color {
        let colors = ["#FF6B6B", "#4ECDC4", "#45B7D1", "#96CEB4", "#FFEAA7"]
        let hex = colors[Int(speakerId) % colors.count]
        return Color(hex: hex) ?? .blue
    }
}

class AudioPlayer: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    
    func load(url: URL) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            duration = audioPlayer?.duration ?? 0
            currentTime = 0
        } catch {
            print("Error loading audio: \(error)")
        }
    }
    
    func play(url: URL) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self as? AVAudioPlayerDelegate
            audioPlayer?.play()
            isPlaying = true
            duration = audioPlayer?.duration ?? 0
            startTimer()
        } catch {
            print("Error playing audio: \(error)")
        }
    }
    
    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        stopTimer()
    }
    
    func resume() {
        audioPlayer?.play()
        isPlaying = true
        startTimer()
    }
    
    func stop() {
        audioPlayer?.stop()
        isPlaying = false
        stopTimer()
        currentTime = 0
    }
    
    func seek(to time: TimeInterval) {
        audioPlayer?.currentTime = time
        currentTime = time
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.currentTime = self?.audioPlayer?.currentTime ?? 0
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

struct EditRecordingSheet: View {
    let recording: Recording
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var title: String
    @State private var tags: String
    @State private var notes: String
    
    init(recording: Recording) {
        self.recording = recording
        _title = State(initialValue: recording.title ?? "Untitled Recording")
        _tags = State(initialValue: recording.tags ?? "")
        _notes = State(initialValue: "")
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("Tags (comma separated)", text: $tags)
                } header: {
                    Text("Recording Info")
                }
                
                Section {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                } header: {
                    Text("Notes")
                }
            }
            .navigationTitle("Edit Recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveChanges()
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func saveChanges() {
        recording.title = title
        recording.tags = tags
        
        try? viewContext.save()
    }
    
    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#if os(iOS)
import UIKit
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#elseif os(macOS)
import AppKit
struct ShareSheet: NSViewRepresentable {
    let items: [Any]
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            let picker = NSSharingServicePicker(items: items)
            picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif

struct ExportOptionsSheet: View {
    let recording: Recording
    @Binding var isProcessing: Bool
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    
    @State private var selectedAudioFormat: ExportFormat = .wav
    @State private var selectedAudioFormats: Set<ExportFormat> = []
    @State private var selectedTranscriptFormat: TranscriptFormat = .txt
    @State private var exportAudio = true
    @State private var exportTranscript = false
    @State private var exportMultipleAudioFormats = false
    @State private var showingShareSheet = false
    @State private var exportURLs: [URL] = []
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    Toggle("Export Audio", isOn: $exportAudio)
                    
                    if exportAudio {
                        Toggle("Export Multiple Formats", isOn: $exportMultipleAudioFormats)
                        
                        if exportMultipleAudioFormats {
                            ForEach(ExportFormat.allCases, id: \.self) { format in
                                Toggle(format.rawValue, isOn: Binding(
                                    get: { selectedAudioFormats.contains(format) },
                                    set: { isOn in
                                        if isOn { selectedAudioFormats.insert(format) } else { selectedAudioFormats.remove(format) }
                                    }
                                ))
                            }
                        } else {
                            Picker("Audio Format", selection: $selectedAudioFormat) {
                                ForEach(ExportFormat.allCases, id: \.self) { format in
                                    Text(format.rawValue).tag(format)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Audio Export")
                }
                
                Section {
                    Toggle("Export Transcript", isOn: $exportTranscript)
                    
                    if exportTranscript {
                        Picker("Transcript Format", selection: $selectedTranscriptFormat) {
                            ForEach(TranscriptFormat.allCases, id: \.self) { format in
                                Text(format.rawValue).tag(format)
                            }
                        }
                    }
                } header: {
                    Text("Transcript Export")
                } footer: {
                    if exportTranscript && recording.transcript == nil {
                        Text("No transcript available")
                            .foregroundColor(.red)
                    }
                }
                
                if appState.canAccess(feature: .exportSpeakerTracks) && recording.detectedSpeakers > 1 {
                    Section {
                        Button(action: exportSpeakerTracks) {
                            HStack {
                                Image(systemName: "person.2.wave.2.fill")
                                Text("Export Individual Speaker Tracks")
                            }
                        }
                        .disabled(isProcessing)
                    } header: {
                        Text("Advanced Export")
                    }
                }
            }
            .navigationTitle("Export Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Export") {
                        performExport()
                    }
                    .disabled(isProcessing || (!exportAudio && !exportTranscript))
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(items: exportURLs)
        }
    }
    
    private func performExport() {
        isProcessing = true
        exportURLs = []
        
        let group = DispatchGroup()
        
        if exportAudio {
            if exportMultipleAudioFormats {
                let formats = selectedAudioFormats.isEmpty ? [selectedAudioFormat] : Array(selectedAudioFormats)
                for format in formats {
                    group.enter()
                    ExportService.shared.exportRecording(recording, format: format) { result in
                        switch result {
                        case .success(let url):
                            exportURLs.append(url)
                        case .failure(let error):
                            print("Export error: \(error)")
                        }
                        group.leave()
                    }
                }
            } else {
                group.enter()
                ExportService.shared.exportRecording(recording, format: selectedAudioFormat) { result in
                    switch result {
                    case .success(let url):
                        exportURLs.append(url)
                    case .failure(let error):
                        print("Export error: \(error)")
                    }
                    group.leave()
                }
            }
        }
        
        if exportTranscript {
            group.enter()
            ExportService.shared.exportTranscript(recording, format: selectedTranscriptFormat) { result in
                switch result {
                case .success(let url):
                    exportURLs.append(url)
                case .failure(let error):
                    print("Export error: \(error)")
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            isProcessing = false
            if !exportURLs.isEmpty {
                showingShareSheet = true
            }
        }
    }
    
    private func exportSpeakerTracks() {
        isProcessing = true
        
        let group = DispatchGroup()
        var urls: [URL] = []
        
        for speakerId in 0..<recording.detectedSpeakers {
            group.enter()
            AudioProcessor.shared.exportSpeakerTrack(
                url: recording.audioURL!,
                speakerId: speakerId,
                segments: recording.speakerSegmentsArray
            ) { result in
                switch result {
                case .success(let url):
                    urls.append(url)
                case .failure(let error):
                    print("Export error: \(error)")
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            isProcessing = false
            exportURLs = urls
            showingShareSheet = true
        }
    }
}

extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
