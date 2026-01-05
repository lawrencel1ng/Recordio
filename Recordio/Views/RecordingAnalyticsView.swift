import SwiftUI
import Charts

struct RecordingAnalyticsView: View {
    let recording: Recording
    @State private var analytics: AnalyticsService.RecordingAnalytics?
    @State private var silences: [AnalyticsService.SilenceMarker] = []
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Summary cards
                summaryCards
                
                // Speaker breakdown
                if let analytics = analytics, !analytics.speakerStats.isEmpty {
                    speakerBreakdown(analytics: analytics)
                }
                
                // Metrics
                if let analytics = analytics {
                    metricsSection(analytics: analytics)
                }
                
                // Silences
                if !silences.isEmpty {
                    silencesSection
                }
            }
            .padding()
        }
        .navigationTitle("Analytics")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadAnalytics()
        }
    }
    
    private var summaryCards: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            StatCard(
                title: "Duration",
                value: formatDuration(recording.duration),
                icon: "clock.fill",
                color: .blue
            )
            
            StatCard(
                title: "Speakers",
                value: "\(recording.detectedSpeakers)",
                icon: "person.2.fill",
                color: .purple
            )
            
            StatCard(
                title: "Words",
                value: "\(analytics?.totalWords ?? 0)",
                icon: "text.bubble.fill",
                color: .green
            )
        }
    }
    
    private func speakerBreakdown(analytics: AnalyticsService.RecordingAnalytics) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Speaker Breakdown", icon: "person.wave.2.fill")
            
            // Pie chart
            if #available(iOS 17.0, *) {
                Chart(analytics.speakerStats, id: \.speakerId) { stat in
                    SectorMark(
                        angle: .value("Time", stat.speakingTime),
                        innerRadius: .ratio(0.5),
                        angularInset: 2
                    )
                    .foregroundStyle(Color(hex: stat.color) ?? .blue)
                    .annotation(position: .overlay) {
                        Text("\(Int(stat.percentage))%")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                }
                .frame(height: 200)
            }
            
            // Speaker list
            VStack(spacing: 12) {
                ForEach(analytics.speakerStats, id: \.speakerId) { stat in
                    SpeakerStatRow(stat: stat)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    private func metricsSection(analytics: AnalyticsService.RecordingAnalytics) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Speech Metrics", icon: "chart.bar.fill")
            
            VStack(spacing: 12) {
                MetricRow(
                    title: "Words per Minute",
                    value: String(format: "%.0f WPM", analytics.averageWPM),
                    description: wpmDescription(wpm: analytics.averageWPM),
                    icon: "speedometer",
                    color: wpmColor(wpm: analytics.averageWPM)
                )
                
                MetricRow(
                    title: "Filler Words",
                    value: "\(analytics.fillerWordCount)",
                    description: fillerDescription(count: analytics.fillerWordCount),
                    icon: "ellipsis.bubble.fill",
                    color: fillerColor(count: analytics.fillerWordCount)
                )
                
                MetricRow(
                    title: "Silence",
                    value: String(format: "%.1f%%", analytics.silencePercentage),
                    description: "Pauses in conversation",
                    icon: "speaker.slash.fill",
                    color: .gray
                )
                
                if analytics.bookmarkCount > 0 {
                    MetricRow(
                        title: "Bookmarks",
                        value: "\(analytics.bookmarkCount)",
                        description: "Key moments marked",
                        icon: "bookmark.fill",
                        color: .orange
                    )
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    private var silencesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Long Pauses", icon: "pause.circle.fill")
            
            VStack(spacing: 8) {
                ForEach(silences) { silence in
                    HStack {
                        Text(formatTimestamp(silence.startTime))
                            .font(.caption)
                            .foregroundColor(.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                        
                        Text(String(format: "%.1fs pause", silence.duration))
                            .font(.subheadline)
                        
                        Spacer()
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    // MARK: - Helpers
    
    private func loadAnalytics() {
        analytics = AnalyticsService.shared.calculateAnalytics(for: recording)
        silences = AnalyticsService.shared.detectSilences(
            in: recording.speakerSegmentsArray,
            totalDuration: recording.duration
        )
    }
    
    private func formatDuration(_ duration: Double) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    private func formatTimestamp(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    private func wpmDescription(wpm: Double) -> String {
        if wpm < 120 { return "Slow pace" }
        if wpm < 150 { return "Normal pace" }
        if wpm < 180 { return "Fast pace" }
        return "Very fast pace"
    }
    
    private func wpmColor(wpm: Double) -> Color {
        if wpm < 120 { return .blue }
        if wpm < 150 { return .green }
        if wpm < 180 { return .orange }
        return .red
    }
    
    private func fillerDescription(count: Int) -> String {
        if count == 0 { return "Excellent!" }
        if count < 5 { return "Very few" }
        if count < 15 { return "Moderate" }
        return "Consider reducing"
    }
    
    private func fillerColor(count: Int) -> Color {
        if count == 0 { return .green }
        if count < 5 { return .blue }
        if count < 15 { return .orange }
        return .red
    }
}

// MARK: - Components

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(color)
            }
            
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

struct SectionHeader: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.blue)
            Text(title)
                .font(.headline)
                .fontWeight(.bold)
        }
    }
}

struct SpeakerStatRow: View {
    let stat: AnalyticsService.SpeakerStats
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: stat.color) ?? .blue)
                .frame(width: 12, height: 12)
            
            Text("Speaker \(stat.speakerId + 1)")
                .font(.subheadline)
                .fontWeight(.medium)
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.1f%%", stat.percentage))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(String(format: "%.0f WPM", stat.averageWPM))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct MetricRow: View {
    let title: String
    let value: String
    let description: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(color)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}


