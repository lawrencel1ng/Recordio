import SwiftUI

struct RecordingsListView: View {
    @StateObject private var recordingManager = RecordingManager.shared
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject var appState: AppState
    
    @State private var searchText = ""
    @State private var selectedSmartFolder: SmartFolder? = .all
    @State private var showingFolderSheet = false
    @State private var showingUpgradePrompt = false
    @State private var upgradePromptType: UpgradePromptType?
    
    enum UpgradePromptType: Identifiable {
        case speaker
        case pro
        case lifetime
        
        var id: String {
            switch self {
            case .speaker: return "speaker"
            case .pro: return "pro"
            case .lifetime: return "lifetime"
            }
        }
    }
    
    @State private var searchResults: [SearchService.SearchResult] = []
    
    var filteredRecordings: [Recording] {
        var recordings = recordingManager.recordings
        
        // If we are searching, we don't filter here because we use searchResults
        if !searchText.isEmpty {
            return [] // We use specific search list instead
        }
        
        switch selectedSmartFolder {
        case .recent:
            recordings = recordings.filter { ($0.createdAt ?? Date.distantPast) > Date().addingTimeInterval(-7 * 24 * 3600) }
        case .meetings:
            recordings = recordings.filter { ($0.title ?? "").localizedCaseInsensitiveContains("meeting") }
        case .lectures:
            recordings = recordings.filter { ($0.title ?? "").localizedCaseInsensitiveContains("lecture") }
        case .interviews:
            recordings = recordings.filter { ($0.title ?? "").localizedCaseInsensitiveContains("interview") }
        case .favorites, .all, .none:
            break
        }
        
        return recordings
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if searchText.isEmpty {
                    smartFoldersScrollView
                    Divider()
                }
                
                if !searchText.isEmpty {
                    searchResultsList
                } else if filteredRecordings.isEmpty {
                    emptyStateView
                } else {
                    recordingsList
                }
            }
            .navigationTitle("Recordings")
            .searchable(text: $searchText, prompt: "Search recordings, transcripts, tags...")
            .onChange(of: searchText) { newValue in
                performSearch(query: newValue)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingFolderSheet = true }) {
                        Image(systemName: "folder.badge.plus")
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingUpgradePrompt = true }) {
                        Image(systemName: "crown.fill")
                            .foregroundColor(appState.currentTier == .free ? .orange : .blue)
                    }
                }
            }
            .sheet(isPresented: $showingFolderSheet) {
                NewFolderSheet()
            }
            .sheet(item: $upgradePromptType) { type in
                UpgradePromptView(promptType: type)
            }
            .onAppear {
                checkUpgradePrompts()
            }
        }
    }
    
    private func performSearch(query: String) {
        if query.isEmpty {
            searchResults = []
        } else {
            searchResults = SearchService.shared.search(query: query, in: viewContext)
        }
    }
    
    private var smartFoldersScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(SmartFolder.allCases, id: \.self) { folder in
                    SmartFolderButton(
                        folder: folder,
                        isSelected: selectedSmartFolder == folder,
                        action: { selectedSmartFolder = folder }
                    )
                }
                
                ForEach(recordingManager.folders, id: \.id) { folder in
                    FolderButton(
                        folder: folder,
                        action: { navigateToFolder(folder) }
                    )
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.systemGroupedBackground))
    }
    
    private var recordingsList: some View {
        List {
            ForEach(filteredRecordings) { recording in
                NavigationLink {
                    RecordingDetailView(recording: recording)
                } label: {
                    RecordingRowView(recording: recording)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            .onDelete(perform: deleteRecordings)
        }
        .listStyle(.plain)
    }
    
    private var searchResultsList: some View {
        List {
            if searchResults.isEmpty {
                Text("No matches found")
                    .foregroundColor(.secondary)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(searchResults) { result in
                    NavigationLink {
                        RecordingDetailView(recording: result.recording)
                    } label: {
                        SearchResultRowView(result: result)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.path")
                .font(.system(size: 80))
                .foregroundColor(.secondary)
            
            Text("No Recordings")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Tap the + button to start recording")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func deleteRecordings(offsets: IndexSet) {
        for index in offsets {
            recordingManager.deleteRecording(filteredRecordings[index])
        }
    }
    
    private func navigateToFolder(_ folder: Folder) {
        
    }
    
    private func checkUpgradePrompts() {
        Task {
            if await UpgradePromptManager.shared.shouldShowSpeakerUpgrade(recordings: recordingManager.recordings) {
                upgradePromptType = .speaker
                await UpgradePromptManager.shared.markSpeakerPromptShown()
            }
        }
    }
}

struct SmartFolderButton: View {
    let folder: SmartFolder
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            action()
        }) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(
                            isSelected ?
                                LinearGradient(colors: folderGradientColors, startPoint: .topLeading, endPoint: .bottomTrailing) :
                                LinearGradient(colors: [Color(.systemGray5), Color(.systemGray5)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: folderIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(isSelected ? .white : .secondary)
                }
                
                Text(folder.rawValue)
                    .font(.caption2)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
    }
    
    private var folderIcon: String {
        switch folder {
        case .all: return "tray.full.fill"
        case .recent: return "clock.fill"
        case .favorites: return "heart.fill"
        case .meetings: return "person.3.fill"
        case .lectures: return "graduationcap.fill"
        case .interviews: return "person.crop.circle.badge.questionmark.fill"
        }
    }
    
    private var folderGradientColors: [Color] {
        switch folder {
        case .all: return [.blue, .cyan]
        case .recent: return [.orange, .yellow]
        case .favorites: return [.pink, .red]
        case .meetings: return [.purple, .blue]
        case .lectures: return [.green, .mint]
        case .interviews: return [.indigo, .purple]
        }
    }
}

struct FolderButton: View {
    let folder: Folder
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            action()
        }) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(Color(.systemGray5))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "folder.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.blue)
                }
                
                Text(folder.name ?? "")
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
    }
}

struct RecordingRowView: View {
    let recording: Recording
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        HStack(spacing: 0) {
            // Accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4)
                .padding(.vertical, 8)
            
            // Content
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(recording.title ?? "Untitled Recording")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                            Text(formatDuration(recording.duration))
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        
                        if appState.canAccess(feature: .speakerDiarization) && recording.detectedSpeakers > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "person.2.fill")
                                Text("\(recording.detectedSpeakers)")
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
                        }
                    }
                    
                    Text((recording.createdAt ?? Date()), style: .relative)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Play indicator
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: "play.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 16)
            .padding(.vertical, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.systemGray5), lineWidth: 0.5)
        )
    }
    
    private func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}



struct NewFolderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var recordingManager = RecordingManager.shared
    
    @State private var folderName = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Folder Name", text: $folderName)
                        .autocapitalization(.words)
                } header: {
                    Text("Create New Folder")
                }
            }
            .navigationTitle("New Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        if !folderName.isEmpty {
                            recordingManager.createFolder(name: folderName)
                            dismiss()
                        }
                    }
                    .disabled(folderName.isEmpty)
                }
            }
        }
    }
}
