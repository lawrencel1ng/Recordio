import SwiftUI
import CoreData
import Charts

struct DashboardView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Recording.createdAt, ascending: false)])
    private var recordings: FetchedResults<Recording>
    
    @State private var selectedTimeRange: TimeRange = .week
    @State private var showingUpgradePrompt = false
    
    enum TimeRange: String, CaseIterable {
        case day = "Today"
        case week = "This Week"
        case month = "This Month"
        case year = "This Year"
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                quickActionsSection
                statsSection
                recentRecordingsSection
            }
            .padding()
        }
        .navigationTitle("Dashboard")
        .sheet(isPresented: $showingUpgradePrompt) {
            ProUpgradePrompt(trigger: .advancedAnalytics)
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Welcome Back!")
                .font(.title)
                .fontWeight(.bold)
            
            Text(greetingMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var greetingMessage: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12:
            return "Good morning! Ready to record?"
        case 12..<17:
            return "Good afternoon! Let's capture your ideas."
        default:
            return "Good evening! Time to reflect on your day."
        }
    }
    
    private var quickActionsSection: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            QuickActionButton(
                title: "New Recording",
                icon: "mic.fill",
                color: .red,
                action: { }
            )
            
            QuickActionButton(
                title: "Import",
                icon: "square.and.arrow.down",
                color: .blue,
                action: { }
            )
            
            QuickActionButton(
                title: "Backup",
                icon: "icloud.fill",
                color: .cyan,
                action: { }
            )
            
            QuickActionButton(
                title: "Settings",
                icon: "gearshape.fill",
                color: .gray,
                action: { }
            )
        }
    }
    
    private var statsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Recording Statistics")
                    .font(.headline)
                
                Spacer()
                
                Picker("", selection: $selectedTimeRange) {
                    ForEach(TimeRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            HStack(spacing: 16) {
                DashboardStatCard(
                    title: "Total Recordings",
                    value: "\(filteredRecordings.count)",
                    icon: "waveform",
                    color: .blue
                )
                
                DashboardStatCard(
                    title: "Total Duration",
                    value: formatDuration(totalDuration),
                    icon: "clock",
                    color: .green
                )
            }
            
            HStack(spacing: 16) {
                DashboardStatCard(
                    title: "Storage Used",
                    value: formatStorage(totalStorage),
                    icon: "externaldrive.fill",
                    color: .orange
                )
                
                DashboardStatCard(
                    title: "Avg Duration",
                    value: formatDuration(filteredRecordings.isEmpty ? 0 : totalDuration / Double(filteredRecordings.count)),
                    icon: "chart.bar.fill",
                    color: .purple
                )
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(16)
    }
    
    private var recentRecordingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Recordings")
                    .font(.headline)
                
                Spacer()
                
                NavigationLink("See All") {
                    RecordingsListView()
                }
                .font(.subheadline)
                .foregroundColor(.blue)
            }
            
            if recentRecordings.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "waveform.badge.mic")
                        .font(.system(size: 50))
                        .foregroundColor(.gray)
                    
                    Text("No recordings yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("Start recording to see your work here")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ForEach(recentRecordings.prefix(5)) { recording in
                    DashboardRecordingRowView(recording: recording)
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                }
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(16)
    }
    
    private var filteredRecordings: [Recording] {
        let calendar = Calendar.current
        let now = Date()
        
        return recordings.filter { recording in
            guard let createdAt = recording.createdAt else { return false }
            
            switch selectedTimeRange {
            case .day:
                return calendar.isDate(createdAt, inSameDayAs: now)
            case .week:
                return calendar.isDate(createdAt, equalTo: now, toGranularity: .weekOfYear)
            case .month:
                return calendar.isDate(createdAt, equalTo: now, toGranularity: .month)
            case .year:
                return calendar.isDate(createdAt, equalTo: now, toGranularity: .year)
            }
        }
    }
    
    private var recentRecordings: [Recording] {
        Array(recordings.prefix(10))
    }
    
    private var totalDuration: TimeInterval {
        filteredRecordings.reduce(0) { $0 + ($1.duration ?? 0) }
    }
    
    private var totalStorage: Int64 {
        filteredRecordings.reduce(Int64(0)) { result, recording in
            guard let audioURL = recording.audioURL,
                  let fileSize = try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int64 else {
                return result
            }
            return result + fileSize
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    private func formatStorage(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(color.opacity(0.1))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(color)
                }
                
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .buttonStyle(.plain)
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
    }
}

struct DashboardStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(color)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

struct DashboardRecordingRowView: View {
    let recording: Recording
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 50, height: 50)
                
                Image(systemName: "waveform")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(recording.title ?? "Untitled Recording")
                    .font(.headline)
                
                if let createdAt = recording.createdAt {
                    Text(createdAt, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Text(formatDuration(recording.duration))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
