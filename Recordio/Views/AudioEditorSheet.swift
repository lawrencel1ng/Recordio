import SwiftUI
import AVFoundation
import CoreData

struct AudioEditorSheet: View {
    let recording: Recording
    @Binding var isProcessing: Bool
    @Binding var error: String?
    @Binding var showError: Bool
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var selectedTab = 0
    @State private var trimStartTime: Double = 0
    @State private var trimEndTime: Double = 0
    @State private var splitTime: Double = 0
    @State private var fadeInDuration: Double = 2.0
    @State private var fadeOutDuration: Double = 2.0
    @State private var crossfadeDuration: Double = 2.0
    @State private var selectedRecordingToMerge: URL?
    @State private var showingFilePicker = false
    
    var body: some View {
        NavigationView {
            TabView(selection: $selectedTab) {
                trimView.tabItem {
                    Label("Trim", systemImage: "scissors")
                }
                
                splitView.tabItem {
                    Label("Split", systemImage: "divide.circle")
                }
                
                fadeView.tabItem {
                    Label("Fade", systemImage: "waveform.path")
                }
                
                mergeView.tabItem {
                    Label("Merge", systemImage: "square.and.arrow.down.on.square")
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
                        applyEdit()
                    }
                    .disabled(isProcessing)
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result)
            }
        }
    }
    
    private var trimView: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Trim Range")
                        .font(.headline)
                    
                    Slider(value: $trimStartTime, in: 0...recording.duration) {
                        Text("Start")
                    }
                    
                    HStack {
                        Text("Start: \(formatTime(trimStartTime))")
                            .font(.caption)
                        Spacer()
                        Text(formatTime(recording.duration))
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                    
                    Slider(value: $trimEndTime, in: 0...recording.duration) {
                        Text("End")
                    }
                    
                    HStack {
                        Text("End: \(formatTime(trimEndTime))")
                            .font(.caption)
                        Spacer()
                    }
                    .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            } header: {
                Text("Trim")
            } footer: {
                Text("Trim removes audio outside the selected range.")
            }
        }
    }
    
    private var splitView: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Split Point")
                        .font(.headline)
                    
                    Slider(value: $splitTime, in: 0...recording.duration)
                    
                    HStack {
                        Text("Split at: \(formatTime(splitTime))")
                            .font(.caption)
                        Spacer()
                        Text(formatTime(recording.duration))
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            } header: {
                Text("Split")
            } footer: {
                Text("Split the recording into two separate files at the selected point.")
            }
        }
    }
    
    private var fadeView: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Fade In")
                        .font(.headline)
                    
                    Slider(value: $fadeInDuration, in: 0.5...10.0, step: 0.5)
                    
                    Text("\(fadeInDuration, specifier: "%.1f") seconds")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Fade Out")
                        .font(.headline)
                    
                    Slider(value: $fadeOutDuration, in: 0.5...10.0, step: 0.5)
                    
                    Text("\(fadeOutDuration, specifier: "%.1f") seconds")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            } header: {
                Text("Fade Effects")
            } footer: {
                Text("Add smooth fade in/out effects to your recording.")
            }
        }
    }
    
    private var mergeView: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Select Recording to Merge")
                        .font(.headline)
                    
                    if let url = selectedRecordingToMerge {
                        HStack {
                            Image(systemName: "waveform")
                                .foregroundColor(.blue)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(url.lastPathComponent)
                                    .font(.subheadline)
                                Text(url.path)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Button("Remove") {
                                selectedRecordingToMerge = nil
                            }
                            .buttonStyle(.borderless)
                        }
                    } else {
                        Button("Select Recording") {
                            showingFilePicker = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.vertical, 8)
                
                if selectedRecordingToMerge != nil {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Crossfade Duration")
                            .font(.headline)
                        
                        Slider(value: $crossfadeDuration, in: 0.5...10.0, step: 0.5)
                        
                        Text("\(crossfadeDuration, specifier: "%.1f") seconds")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            } header: {
                Text("Merge")
            } footer: {
                Text("Merge another recording with this one using a smooth crossfade.")
            }
        }
    }
    
    private func applyEdit() {
        isProcessing = true
        
        switch selectedTab {
        case 0:
            applyTrim()
        case 1:
            applySplit()
        case 2:
            applyFade()
        case 3:
            applyMerge()
        default:
            isProcessing = false
        }
    }
    
    private func applyTrim() {
        guard let url = recording.audioURL else {
            error = "No audio file found"
            showError = true
            isProcessing = false
            return
        }
        
        guard trimStartTime < trimEndTime else {
            error = "Start time must be before end time"
            showError = true
            isProcessing = false
            return
        }
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let outputPath = documentsPath.appendingPathComponent("Edited", isDirectory: true)
        
        do {
            try FileManager.default.createDirectory(at: outputPath, withIntermediateDirectories: true)
            let outputURL = outputPath.appendingPathComponent("\(recording.title ?? "Recording")_trimmed.m4a")
            
            try AudioEditorService.shared.trimAudio(
                from: url,
                startTime: trimStartTime,
                endTime: trimEndTime,
                outputURL: outputURL
            )
            
            createNewRecording(from: outputURL, title: "\(recording.title ?? "Recording") (Trimmed)")
            isProcessing = false
            dismiss()
        } catch {
            self.error = error.localizedDescription
            showError = true
            isProcessing = false
        }
    }
    
    private func applySplit() {
        guard let url = recording.audioURL else {
            error = "No audio file found"
            showError = true
            isProcessing = false
            return
        }
        
        do {
            let splitURLs = try AudioEditorService.shared.splitAudio(from: url, atTime: splitTime)
            
            for (index, splitURL) in splitURLs.enumerated() {
                createNewRecording(from: splitURL, title: "\(recording.title ?? "Recording") Part \(index + 1)")
            }
            
            isProcessing = false
            dismiss()
        } catch {
            self.error = error.localizedDescription
            showError = true
            isProcessing = false
        }
    }
    
    private func applyFade() {
        guard let url = recording.audioURL else {
            error = "No audio file found"
            showError = true
            isProcessing = false
            return
        }
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let outputPath = documentsPath.appendingPathComponent("Edited", isDirectory: true)
        
        do {
            try FileManager.default.createDirectory(at: outputPath, withIntermediateDirectories: true)
            let outputURL = outputPath.appendingPathComponent("\(recording.title ?? "Recording")_faded.m4a")
            
            try AudioEditorService.shared.fadeIn(url: url, duration: fadeInDuration, outputURL: outputURL)
            try AudioEditorService.shared.fadeOut(url: outputURL, duration: fadeOutDuration, outputURL: outputURL)
            
            createNewRecording(from: outputURL, title: "\(recording.title ?? "Recording") (Faded)")
            isProcessing = false
            dismiss()
        } catch {
            self.error = error.localizedDescription
            showError = true
            isProcessing = false
        }
    }
    
    private func applyMerge() {
        guard let url = recording.audioURL,
              let mergeURL = selectedRecordingToMerge else {
            error = "Please select a recording to merge"
            showError = true
            isProcessing = false
            return
        }
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let outputPath = documentsPath.appendingPathComponent("Edited", isDirectory: true)
        
        do {
            try FileManager.default.createDirectory(at: outputPath, withIntermediateDirectories: true)
            let outputURL = outputPath.appendingPathComponent("\(recording.title ?? "Recording")_merged.m4a")
            
            try AudioEditorService.shared.applyCrossfade(
                from: url,
                to: mergeURL,
                crossfadeDuration: crossfadeDuration,
                outputURL: outputURL
            )
            
            createNewRecording(from: outputURL, title: "\(recording.title ?? "Recording") (Merged)")
            isProcessing = false
            dismiss()
        } catch {
            self.error = error.localizedDescription
            showError = true
            isProcessing = false
        }
    }
    
    private func createNewRecording(from url: URL, title: String) {
        let newRecording = Recording(context: viewContext)
        newRecording.id = UUID()
        newRecording.title = title
        newRecording.createdAt = Date()
        newRecording.duration = AVAsset(url: url).duration.seconds
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recordingsPath = documentsPath.appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: recordingsPath, withIntermediateDirectories: true)
        
        let filename = "\(UUID().uuidString).m4a"
        let destinationURL = recordingsPath.appendingPathComponent(filename)
        
        try? FileManager.default.copyItem(at: url, to: destinationURL)
        newRecording.audioURL = destinationURL
        
        try? viewContext.save()
    }
    
    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                selectedRecordingToMerge = url
            }
        case .failure(let error):
            self.error = error.localizedDescription
            showError = true
        }
    }
    
    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
