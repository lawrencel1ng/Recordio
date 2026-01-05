import SwiftUI
import AVFoundation
import CoreData

struct RecordingView: View {
    @StateObject private var audioEngine = AudioEngine.shared
    @StateObject private var recordingManager = RecordingManager.shared
    @StateObject private var liveTranscription = LiveTranscriptionService.shared
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    
    @State private var recordingTitle = ""
    @State private var showingTitleSheet = false
    @State private var isProcessing = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var bookmarks: [(timestamp: TimeInterval, label: String)] = []
    @State private var showLiveTranscript = true
    @AppStorage("largeRecordButton") private var largeRecordButton: Bool = false
    @AppStorage("prebufferSeconds") private var prebufferSeconds: Int = 0
    @State private var showingAdvanced = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                header
                
                if let warning = audioEngine.systemWarning {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text(warning)
                            .font(.caption)
                            .foregroundColor(.yellow)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .background(Color.yellow.opacity(0.1))
                }
                
                if audioEngine.isRecording {
                    recordingContent
                } else {
                    idleContent
                }
                
                Spacer()
                
                recordingControls
                    .padding(.bottom, 40)
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showingTitleSheet) {
            TitleSheet(recordingTitle: $recordingTitle, bookmarks: bookmarks, onSave: saveRecording)
        }
        .sheet(isPresented: $showingAdvanced) {
            NavigationView {
                AdvancedSettingsView()
            }
        }
        .alert("Recording Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .onReceive(NotificationCenter.default.publisher(for: .recordingDidFinish)) { notification in
            if let url = notification.object as? URL {
                showTitleSheet(for: url)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickCaptureRequested)) { _ in
            if !audioEngine.isRecording {
                startRecording()
            }
        }
        .onAppear {
            if prebufferSeconds > 0 {
                try? audioEngine.startPrebuffering()
            }
        }
        .onDisappear {
            audioEngine.stopPrebuffering()
        }
    }
    
    private var header: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding()
            }
            
            Spacer()
            
            Text(audioEngine.isRecording ? "Recording" : "New Recording")
                .font(.headline)
                .foregroundColor(.white)
            
            Spacer()
            
            // Live transcript toggle
            if audioEngine.isRecording {
                Button(action: { showLiveTranscript.toggle() }) {
                    Image(systemName: showLiveTranscript ? "text.bubble.fill" : "text.bubble")
                        .font(.title2)
                        .foregroundColor(showLiveTranscript ? .blue : .white)
                        .padding()
                }
            } else {
                Button(action: { showingAdvanced = true }) {
                    Image(systemName: "gearshape.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding()
                }
            }
        }
        .padding(.top)
        .padding(.horizontal)
    }
    
    private var recordingContent: some View {
        VStack(spacing: 16) {
            TimerDisplay(duration: audioEngine.currentDuration)
            
            WaveformView(audioLevel: audioEngine.audioLevel, isRecording: audioEngine.isRecording)
                .frame(height: 120)
            
            // Bookmark button
            HStack(spacing: 20) {
                Button(action: addBookmark) {
                    HStack(spacing: 8) {
                        Image(systemName: "bookmark.fill")
                        Text("Mark")
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(colors: [.orange, .pink], startPoint: .leading, endPoint: .trailing)
                    )
                    .cornerRadius(20)
                }
                
                if !bookmarks.isEmpty {
                    Text("\(bookmarks.count) bookmark\(bookmarks.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Transcript preview panel
            if showLiveTranscript {
                liveTranscriptView
            }
        }
    }
    
    private var liveTranscriptView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                Text("Transcript Preview")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: "lock.shield.fill")
                        .font(.caption2)
                    Text("Offline")
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.1))
                .cornerRadius(8)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                if liveTranscription.isTranscribing {
                    if liveTranscription.liveTranscript.isEmpty {
                        Text("Listening...")
                            .font(.body)
                            .italic()
                            .foregroundColor(.white.opacity(0.7))
                    } else {
                        Text(liveTranscription.liveTranscript)
                            .font(.body)
                            .foregroundColor(.white)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("Recording in progress...")
                        .font(.body)
                        .foregroundColor(.white.opacity(0.9))
                    
                    Text("Transcript will be generated after recording stops.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                }
                
                // Status indicators
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform")
                        Text("Capturing audio")
                    }
                    .font(.caption2)
                    .foregroundColor(.blue)
                    
                    if !bookmarks.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "bookmark.fill")
                            Text("\(bookmarks.count)")
                        }
                        .font(.caption2)
                        .foregroundColor(.orange)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.horizontal)
    }
    
    private var idleContent: some View {
        VStack(spacing: 30) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.1))
                    .frame(width: 160, height: 160)
                
                Circle()
                    .fill(Color.red.opacity(0.2))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.red.opacity(0.5))
            }
            
            VStack(spacing: 12) {
                Text("Ready to Record")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Text("Tap the red button to start recording")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Privacy badge
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .font(.caption)
                Text("100% Private • Processed on Device")
                    .font(.caption)
            }
            .foregroundColor(.green)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.green.opacity(0.15))
            .cornerRadius(20)
            
            Spacer()
        }
    }
    
    private var recordingControls: some View {
        HStack(spacing: 40) {
            if audioEngine.isRecording {
                Button(action: stopRecording) {
                    ZStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: largeRecordButton ? 110 : 80, height: largeRecordButton ? 110 : 80)
                            .shadow(color: .red.opacity(0.5), radius: 10, x: 0, y: 5)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white)
                                    .frame(width: largeRecordButton ? 38 : 30, height: largeRecordButton ? 38 : 30)
                            )
                    }
                }
                .accessibilityLabel("Stop Recording")
            } else if audioEngine.isPaused {
                Button(action: resumeRecording) {
                    ZStack {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: largeRecordButton ? 110 : 80, height: largeRecordButton ? 110 : 80)
                            .shadow(color: .orange.opacity(0.5), radius: 10, x: 0, y: 5)
                            .overlay(
                                Image(systemName: "play.fill")
                                    .font(.title2)
                                    .foregroundColor(.white)
                            )
                    }
                }
                .accessibilityLabel("Resume Recording")
            } else {
                Button(action: startRecording) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .frame(width: largeRecordButton ? 110 : 80, height: largeRecordButton ? 110 : 80)
                            .shadow(color: .red.opacity(0.5), radius: 10, x: 0, y: 5)
                    }
                }
                .accessibilityLabel("Start Recording")
            }
            
            if audioEngine.isRecording {
                Button(action: pauseRecording) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: largeRecordButton ? 80 : 60, height: largeRecordButton ? 80 : 60)
                            .overlay(
                                Image(systemName: "pause.fill")
                                    .font(.title3)
                                    .foregroundColor(.white)
                            )
                    }
                }
                .accessibilityLabel("Pause Recording")
            }
        }
    }
    
    // MARK: - Actions
    
    private func startRecording() {
        do {
            try audioEngine.startRecording()
            
            // Start live transcription if authorized
            if liveTranscription.isAuthorized, let engine = audioEngine.avAudioEngine {
                try liveTranscription.startLiveTranscription(audioEngine: engine)
            }
            
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
    
    private func stopRecording() {
        liveTranscription.stopLiveTranscription()
        audioEngine.stopRecording()
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
    
    private func pauseRecording() {
        audioEngine.pauseRecording()
        
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    private func resumeRecording() {
        audioEngine.resumeRecording()
        
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
    
    private func addBookmark() {
        let timestamp = audioEngine.currentDuration
        bookmarks.append((timestamp: timestamp, label: "Bookmark \(bookmarks.count + 1)"))
        
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    private func showTitleSheet(for url: URL) {
        recordingTitle = "Recording \(Date().formatted(date: .abbreviated, time: .shortened))"
        showingTitleSheet = true
    }
    
    private func saveRecording() {
        guard let url = audioEngine.currentRecordingURL else { return }
        
        isProcessing = true
        
        var finalURL = url
        if audioEngine.hasPrebuffer() {
            if let preURL = try? audioEngine.exportPrebufferToFile() {
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let outputPath = documentsPath.appendingPathComponent("Edited", isDirectory: true)
                try? FileManager.default.createDirectory(at: outputPath, withIntermediateDirectories: true)
                let mergedURL = outputPath.appendingPathComponent("Merged_\(UUID().uuidString).m4a")
                if (try? AudioEditorService.shared.mergeAudio(recordings: [preURL, url], outputURL: mergedURL)) != nil {
                    finalURL = mergedURL
                }
            }
        }
        
        let recording = recordingManager.createRecording(
            title: recordingTitle,
            audioURL: finalURL,
            duration: audioEngine.currentDuration,
            transcript: liveTranscription.liveTranscript
        )
        
        // Save bookmarks
        for bookmark in bookmarks {
            recordingManager.addBookmark(to: recording, timestamp: bookmark.timestamp, label: bookmark.label)
        }
        
        // Clear bookmarks for next recording
        bookmarks = []
        liveTranscription.reset()
        
        if appState.canAccess(feature: .speakerDiarization) {
            processRecording(url: url)
        } else {
            isProcessing = false
            dismiss()
        }
    }
    
    @AppStorage("autoEnhanceAudio") private var autoEnhanceAudio = false
    @AppStorage("autoReduceNoise") private var autoReduceNoise = false
    
    private func processRecording(url: URL) {
        // Chain operations: Audio Processing -> Diarization -> Transcription -> Analytics
        
        func runDiarizationAndTranscription(on processedURL: URL) {
            SpeakerDiarizationService.shared.processAudioFile(processedURL) { result in
                switch result {
                case .success(let segments):
                    if appState.canAccess(feature: .aiSummaries) {
                        TranscriptionService.shared.transcribeAudioFile(processedURL, speakerSegments: segments) { transcriptionResult in
                            switch transcriptionResult {
                            case .success(let result):
                                if let recording = recordingManager.recordings.first {
                                    recordingManager.updateRecording(
                                        recording,
                                        speakerSegments: segments,
                                        transcript: result.fullTranscript,
                                        segmentTranscripts: result.segmentTranscripts
                                    )
                                    
                                    // Calculate analytics from full transcript
                                    let wordCount = AnalyticsService.shared.calculateWordCount(in: result.fullTranscript)
                                    let fillerCount = AnalyticsService.shared.countFillerWords(in: result.fullTranscript)
                                    recordingManager.updateAnalytics(recording, wordCount: wordCount, fillerWordCount: fillerCount)
                                    
                                    // Update audio URL if it changed during processing
                                    if processedURL != url {
                                        recording.audioURL = processedURL
                                        try? viewContext.save()
                                    }
                                }
                                isProcessing = false
                                dismiss()
                            case .failure:
                                if let recording = recordingManager.recordings.first {
                                    recordingManager.updateRecording(recording, speakerSegments: segments, transcript: recording.transcript)
                                    if processedURL != url {
                                        recording.audioURL = processedURL
                                        try? viewContext.save()
                                    }
                                }
                                isProcessing = false
                                dismiss()
                            }
                        }
                    } else {
                        if let recording = recordingManager.recordings.first {
                            recordingManager.updateRecording(recording, speakerSegments: segments, transcript: recording.transcript)
                            if processedURL != url {
                                recording.audioURL = processedURL
                                try? viewContext.save()
                            }
                        }
                        isProcessing = false
                        dismiss()
                    }
                case .failure:
                    isProcessing = false
                    dismiss()
                }
            }
        }
        
        // Check for audio enhancements
        if appState.canAccess(feature: .audioEnhancement) && autoEnhanceAudio {
            AudioProcessor.shared.enhanceAudio(url: url) { result in
                switch result {
                case .success(let enhancedURL):
                    // If noise reduction is also on
                    if appState.canAccess(feature: .aiNoiseReduction) && autoReduceNoise {
                        AudioProcessor.shared.reduceNoise(url: enhancedURL) { nrResult in
                            switch nrResult {
                            case .success(let finalURL):
                                runDiarizationAndTranscription(on: finalURL)
                            case .failure:
                                runDiarizationAndTranscription(on: enhancedURL)
                            }
                        }
                    } else {
                        runDiarizationAndTranscription(on: enhancedURL)
                    }
                case .failure:
                    // If enhance failed, try noise reduction on original
                    if appState.canAccess(feature: .aiNoiseReduction) && autoReduceNoise {
                        AudioProcessor.shared.reduceNoise(url: url) { nrResult in
                            switch nrResult {
                            case .success(let finalURL):
                                runDiarizationAndTranscription(on: finalURL)
                            case .failure:
                                runDiarizationAndTranscription(on: url)
                            }
                        }
                    } else {
                        runDiarizationAndTranscription(on: url)
                    }
                }
            }
        } else if appState.canAccess(feature: .aiNoiseReduction) && autoReduceNoise {
            // Only noise reduction
            AudioProcessor.shared.reduceNoise(url: url) { result in
                switch result {
                case .success(let finalURL):
                    runDiarizationAndTranscription(on: finalURL)
                case .failure:
                    runDiarizationAndTranscription(on: url)
                }
            }
        } else {
            // No audio processing
            runDiarizationAndTranscription(on: url)
        }
    }
}

struct TimerDisplay: View {
    let duration: TimeInterval
    
    var body: some View {
        Text(formatDuration(duration))
            .font(.system(size: 64, weight: .thin, design: .monospaced))
            .foregroundColor(.white)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

struct WaveformView: View {
    let audioLevel: Float
    let isRecording: Bool
    
    @State private var bars: [CGFloat] = Array(repeating: 0.2, count: 40)
    @State private var realtimeSamples: [Float] = []
    @State private var updateTimer: Timer?
    
    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(0..<bars.count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [.red, .orange, .yellow],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 4, height: barHeight(for: index))
                    .animation(.easeInOut(duration: 0.08), value: bars[index])
            }
        }
        .onAppear {
            startWaveformAnimation()
        }
        .onDisappear {
            updateTimer?.invalidate()
        }
        .onChange(of: isRecording) { newValue in
            if !newValue {
                updateTimer?.invalidate()
                bars = Array(repeating: 0.2, count: 40)
                realtimeSamples = []
            }
        }
    }
    
    private func barHeight(for index: Int) -> CGFloat {
        if !realtimeSamples.isEmpty {
            let sampleIndex = min(Int(Double(index) / Double(bars.count) * Double(realtimeSamples.count)), realtimeSamples.count - 1)
            return CGFloat(realtimeSamples[sampleIndex]) * 120
        }
        return bars[index] * 120
    }
    
    private func startWaveformAnimation() {
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
            if isRecording {
                let normalized = max(0, (audioLevel + 60) / 60)
                let newSample = Float.random(in: 0.1...1.0) * Float(normalized)
                
                DispatchQueue.main.async {
                    if realtimeSamples.count > 40 {
                        realtimeSamples.removeFirst()
                    }
                    realtimeSamples.append(newSample)
                    
                    let waveform = WaveformService.shared.generateRealtimeWaveform(samples: realtimeSamples, downsampleTo: 40)
                    self.bars = waveform.map { CGFloat($0) }
                }
            } else {
                timer.invalidate()
                bars = Array(repeating: 0.2, count: 40)
                realtimeSamples = []
            }
        }
    }
}

struct TitleSheet: View {
    @Binding var recordingTitle: String
    let bookmarks: [(timestamp: TimeInterval, label: String)]
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recording Title")
                        .font(.headline)
                    
                    TextField("Enter title", text: $recordingTitle)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.words)
                }
                .padding()
                
                if !bookmarks.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Bookmarks (\(bookmarks.count))")
                            .font(.headline)
                        
                        ForEach(Array(bookmarks.enumerated()), id: \.offset) { index, bookmark in
                            HStack {
                                Image(systemName: "bookmark.fill")
                                    .foregroundColor(.orange)
                                Text(formatTimestamp(bookmark.timestamp))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(bookmark.label)
                                    .font(.subheadline)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                Spacer()
                
                Button(action: {
                    onSave()
                    dismiss()
                }) {
                    Text("Save Recording")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                        )
                        .cornerRadius(12)
                }
                .padding()
            }
            .navigationTitle("Save Recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
