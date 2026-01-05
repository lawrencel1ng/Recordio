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
                NavigationView {
                    DashboardView(selectedTab: $selectedTab)
                }
                .tabItem {
                    Label("Dashboard", systemImage: "chart.bar.fill")
                }
                .tag(0)

                RecordingsListView()
                    .tabItem {
                        Label("Recordings", systemImage: "tray.fill")
                    }
                    .tag(1)
                
                RecordingViewWrapper()
                    .tabItem {
                        Label("Record", systemImage: "plus.circle.fill")
                    }
                    .tag(2)
                
                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                    .tag(3)
            }
            .accentColor(.blue)
            .onOpenURL { url in
                if url.scheme?.lowercased() == "recordio" && (url.host?.lowercased() == "capture" || url.path.lowercased().contains("capture")) {
                    selectedTab = 2
                    NotificationCenter.default.post(name: .quickCaptureRequested, object: nil)
                }
            }
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
