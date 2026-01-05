import SwiftUI
import AVFoundation
import Combine

struct AudioComparisonView: View {
    let originalURL: URL
    let enhancedURL: URL
    let title: String
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var player = ComparisonAudioPlayer()
    
    @State private var isPlayingOriginal = false
    @State private var isPlayingEnhanced = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                headerView
                
                waveformsView
                
                controlsView
                
                saveButtonsView
            }
            .padding()
            .navigationTitle("Audio Comparison")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            Text("Compare the original and enhanced versions")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private var waveformsView: some View {
        VStack(spacing: 16) {
            WaveformComparisonCard(
                title: "Original",
                url: originalURL,
                isPlaying: $isPlayingOriginal,
                color: .gray,
                player: player
            )
            
            WaveformComparisonCard(
                title: "Enhanced",
                url: enhancedURL,
                isPlaying: $isPlayingEnhanced,
                color: .blue,
                player: player
            )
        }
    }
    
    private var controlsView: some View {
        HStack(spacing: 20) {
            Button(action: { playABComparison() }) {
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .frame(width: 60, height: 60)
                        
                        Image(systemName: "repeat")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    
                    Text("A/B Test")
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
            .buttonStyle(.plain)
            
            Button(action: { playSideBySide() }) {
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(colors: [.green, .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .frame(width: 60, height: 60)
                        
                        Image(systemName: "rectangle.split.2x1")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    
                    Text("Side by Side")
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
            .buttonStyle(.plain)
        }
    }
    
    private var saveButtonsView: some View {
        VStack(spacing: 12) {
            Button(action: { saveOriginal() }) {
                HStack {
                    Image(systemName: "square.and.arrow.down")
                    Text("Save Original")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue.opacity(0.1))
                .foregroundColor(.blue)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            
            Button(action: { saveEnhanced() }) {
                HStack {
                    Image(systemName: "sparkles")
                    Text("Save Enhanced")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                )
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
        }
    }
    
    private func playABComparison() {
        player.stop()
        
        Task {
            await player.playComparison(original: originalURL, enhanced: enhancedURL, mode: .ab)
        }
    }
    
    private func playSideBySide() {
        player.stop()
        
        Task {
            await player.playComparison(original: originalURL, enhanced: enhancedURL, mode: .sideBySide)
        }
    }
    
    private func saveOriginal() {
        // Save original URL to recordings
        dismiss()
    }
    
    private func saveEnhanced() {
        // Save enhanced URL to recordings
        dismiss()
    }
}

struct WaveformComparisonCard: View {
    let title: String
    let url: URL
    @Binding var isPlaying: Bool
    let color: Color
    @ObservedObject var player: ComparisonAudioPlayer
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                
                Spacer()
                
                if isPlaying {
                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundColor(color)
                        .symbolEffect(.pulse)
                }
            }
            
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.1))
                    .frame(height: 60)
                
                ProgressView(value: player.progress(for: url))
                    .tint(color)
            }
            
            HStack {
                Text("\(formatDuration(player.currentTime(for: url)))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(formatDuration(player.duration(for: url)))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

@MainActor
class ComparisonAudioPlayer: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    
    private var player: AVAudioPlayer?
    private var timer: Timer?
    
    enum PlaybackMode {
        case original
        case enhanced
        case ab
        case sideBySide
    }
    
    func playComparison(original: URL, enhanced: URL, mode: PlaybackMode) async {
        do {
            switch mode {
            case .ab:
                await playABTest(original: original, enhanced: enhanced)
            case .sideBySide:
                await playSideBySide(original: original, enhanced: enhanced)
            default:
                break
            }
        } catch {
            print("Error playing comparison: \(error)")
        }
    }
    
    private func playABTest(original: URL, enhanced: URL) async {
        for i in 0..<3 {
            let url = i % 2 == 0 ? original : enhanced
            await playURL(url)
            sleep(2)
        }
    }
    
    private func playSideBySide(original: URL, enhanced: URL) async {
        await playURL(original)
        await playURL(enhanced)
    }
    
    private func playURL(_ url: URL) async {
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            self.player = player
            self.duration = player.duration
            self.isPlaying = true
            player.play()
            
            await MainActor.run {
                startTimer()
            }
            
            while player.isPlaying {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            
            self.isPlaying = false
            stopTimer()
        } catch {
            print("Error playing: \(error)")
        }
    }
    
    func stop() {
        player?.stop()
        isPlaying = false
        stopTimer()
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.currentTime = self?.player?.currentTime ?? 0
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    func currentTime(for url: URL) -> TimeInterval {
        return currentTime
    }
    
    func duration(for url: URL) -> TimeInterval {
        return duration
    }
    
    func progress(for url: URL) -> Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }
}
