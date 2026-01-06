import SwiftUI
import CoreData

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingOnboarding = !AppState.shared.hasSeenOnboarding
    
    var body: some View {
        if showingOnboarding {
            OnboardingView(isPresented: $showingOnboarding)
        } else {
            TabView(selection: $appState.selectedTab) {
                NavigationView {
                    DashboardView(selectedTab: $appState.selectedTab)
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
                    appState.selectedTab = 2
                    appState.shouldAutoStartRecording = true
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
        ZStack {
            Color.clear
            
            VStack(spacing: 12) {
                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.red)
                Text("Ready to Record")
                    .font(.headline)
            }
        }
        .onAppear {
            // Auto-present recording sheet when tab is selected
            appState.shouldAutoStartRecording = true
            showingRecording = true
        }
        .onChange(of: appState.selectedTab) { tab in
            if tab == 2 {
                appState.shouldAutoStartRecording = true
                showingRecording = true
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showingRecording, onDismiss: {
            // If dismissed without changing tab (e.g. cancelled), switch back to Dashboard or Recordings to avoid loop?
            // Or just stay here. If user cancelled, they are here.
            // If they saved, we likely switched tab already.
            if appState.selectedTab == 2 {
                // If we are still on tab 2 after dismiss, it means user cancelled.
                // We should probably switch away to avoid re-triggering onAppear if they leave and come back?
                // For now, let's switch to Dashboard to be safe and clean.
                appState.selectedTab = 0
            }
        }) {
            RecordingView()
                .environmentObject(appState)
                .environment(\.managedObjectContext, viewContext)
        }
        #else
        .sheet(isPresented: $showingRecording, onDismiss: {
            if appState.selectedTab == 2 {
                appState.selectedTab = 0
            }
        }) {
            RecordingView()
                .environmentObject(appState)
                .environment(\.managedObjectContext, viewContext)
        }
        #endif
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState.shared)
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
