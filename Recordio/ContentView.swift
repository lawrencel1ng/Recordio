import SwiftUI
import CoreData

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0
    @State private var showingOnboarding = !AppState.shared.hasSeenOnboarding
    @State private var showingRecording = false
    
    var body: some View {
        if showingOnboarding {
            OnboardingView(isPresented: $showingOnboarding)
        } else {
            TabView(selection: $selectedTab) {
                RecordingsListView()
                    .tabItem {
                        Label("Recordings", systemImage: "tray.fill")
                    }
                    .tag(0)
                
                RecordingViewWrapper()
                    .tabItem {
                        Label("Record", systemImage: "plus.circle.fill")
                    }
                    .tag(1)
                
                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                    .tag(2)
            }
            .accentColor(.blue)
        }
    }
}

struct RecordingViewWrapper: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showingRecording = false
    
    var body: some View {
        Button(action: { showingRecording = true }) {
            VStack(spacing: 12) {
                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.red)
                
                Text("Tap to Record")
                    .font(.headline)
                
                Text("Create a new recording")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .fullScreenCover(isPresented: $showingRecording) {
            RecordingView()
                .environmentObject(appState)
                .environment(\.managedObjectContext, viewContext)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState.shared)
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
