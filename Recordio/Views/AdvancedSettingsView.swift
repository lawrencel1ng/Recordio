import SwiftUI

struct AdvancedSettingsView: View {
    @EnvironmentObject var appState: AppState
    
    @AppStorage("transcriptionLanguage") private var transcriptionLanguage = "en-US"
    @AppStorage("enableTimestamps") private var enableTimestamps = true
    @AppStorage("noiseGateThreshold") private var noiseGateThreshold = 0.02
    @AppStorage("compressionRatio") private var compressionRatio = 4.0
    
    let languages = [
        ("en-US", "English (US)"),
        ("en-GB", "English (UK)"),
        ("es-ES", "Spanish"),
        ("fr-FR", "French"),
        ("de-DE", "German"),
        ("it-IT", "Italian"),
        ("pt-BR", "Portuguese"),
        ("ja-JP", "Japanese"),
        ("zh-CN", "Chinese (Simplified)")
    ]
    
    var body: some View {
        Form {
            Section {
                Picker("Transcription Language", selection: $transcriptionLanguage) {
                    ForEach(languages, id: \.0) { code, name in
                        Text(name).tag(code)
                    }
                }
                
                Toggle("Include Timestamps", isOn: $enableTimestamps)
            } header: {
                Text("Transcription")
            } footer: {
                Text("Language affects on-device speech recognition accuracy")
            }
            
            if appState.canAccess(feature: .audioEnhancement) {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Noise Gate Threshold")
                            Spacer()
                            Text(String(format: "%.1f%%", noiseGateThreshold * 100))
                                .foregroundColor(.secondary)
                        }
                        
                        Slider(value: $noiseGateThreshold, in: 0.01...0.1, step: 0.005)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Compression Ratio")
                            Spacer()
                            Text(String(format: "%.1f:1", compressionRatio))
                                .foregroundColor(.secondary)
                        }
                        
                        Slider(value: $compressionRatio, in: 1.0...8.0, step: 0.5)
                    }
                    
                    Button("Reset to Defaults") {
                        noiseGateThreshold = 0.02
                        compressionRatio = 4.0
                    }
                    .foregroundColor(.blue)
                } header: {
                    Text("Audio Processing")
                } footer: {
                    Text("Adjust these settings for fine-tuned audio enhancement")
                }
            }
            
            Section {
                NavigationLink {
                    DataStorageView()
                } label: {
                    HStack {
                        Image(systemName: "internaldrive")
                            .foregroundColor(.blue)
                        Text("Storage & Data")
                    }
                }
                
                NavigationLink {
                    PrivacyView()
                } label: {
                    HStack {
                        Image(systemName: "hand.raised.fill")
                            .foregroundColor(.blue)
                        Text("Privacy")
                    }
                }
            } header: {
                Text("Data")
            }
        }
        .navigationTitle("Advanced")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DataStorageView: View {
    @State private var storageUsed: String = "Calculating..."
    
    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Recordings Storage")
                    Spacer()
                    Text(storageUsed)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Transcripts")
                    Spacer()
                    Text("Stored locally")
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Storage Usage")
            }
            
            Section {
                Button("Clear Processed Files") {
                    // Clear cached processed files
                }
                .foregroundColor(.orange)
                
                Button("Delete All Recordings") {
                    // Confirm and delete
                }
                .foregroundColor(.red)
            } header: {
                Text("Manage Data")
            } footer: {
                Text("Deleting recordings cannot be undone")
            }
        }
        .navigationTitle("Storage & Data")
        .onAppear {
            calculateStorage()
        }
    }
    
    private func calculateStorage() {
        DispatchQueue.global().async {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let recordingsPath = documentsPath.appendingPathComponent("Recordings")
            
            var size: Int64 = 0
            if let enumerator = FileManager.default.enumerator(at: recordingsPath, includingPropertiesForKeys: [.fileSizeKey]) {
                for case let fileURL as URL in enumerator {
                    if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        size += Int64(fileSize)
                    }
                }
            }
            
            DispatchQueue.main.async {
                storageUsed = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            }
        }
    }
}

struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "lock.shield.fill")
                            .font(.title)
                            .foregroundColor(.green)
                        Text("100% Private")
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    
                    Text("All your recordings and transcripts are processed and stored entirely on your device. Nothing is ever sent to external servers.")
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
                
                VStack(alignment: .leading, spacing: 16) {
                    PrivacyItem(
                        icon: "waveform",
                        title: "Audio Recordings",
                        description: "Stored only in your device's local storage"
                    )
                    
                    PrivacyItem(
                        icon: "text.bubble.fill",
                        title: "Transcriptions",
                        description: "Processed using Apple's on-device speech recognition"
                    )
                    
                    PrivacyItem(
                        icon: "person.2.fill",
                        title: "Speaker Analysis",
                        description: "Performed locally without cloud processing"
                    )
                    
                    PrivacyItem(
                        icon: "chart.bar.fill",
                        title: "Analytics",
                        description: "Calculated entirely on your device"
                    )
                }
                .padding()
                
                Spacer()
            }
            .padding()
        }
        .navigationTitle("Privacy")
    }
}

struct PrivacyItem: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}
