import SwiftUI
import CoreData

@main
struct RecordioApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var appState = AppState.shared
    @StateObject private var biometricAuth = BiometricAuthService.shared
    
    var body: some Scene {
        WindowGroup {
            if biometricAuth.isBiometricEnabled {
                LockedContentView()
                    .environment(\.managedObjectContext, persistenceController.container.viewContext)
                    .environmentObject(appState)
                    .environmentObject(biometricAuth)
            } else {
                ContentView()
                    .environment(\.managedObjectContext, persistenceController.container.viewContext)
                    .environmentObject(appState)
                    .environmentObject(biometricAuth)
            }
        }
    }
}

struct LockedContentView: View {
    @EnvironmentObject var biometricAuth: BiometricAuthService
    @State private var isAuthenticated = false
    @State private var isAuthenticating = false
    @State private var authError: String?
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if isAuthenticated {
                ContentView()
            } else {
                lockView
            }
        }
    }
    
    private var lockView: some View {
        VStack(spacing: 30) {
            Spacer()
            
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            VStack(spacing: 12) {
                Text("Recordio is Locked")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("Use \(biometricAuth.biometricName) to unlock")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            if let error = authError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
            }
            
            Button(action: authenticate) {
                HStack {
                    if isAuthenticating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: biometricIcon)
                            .font(.title)
                    }
                    
                    Text(isAuthenticating ? "Authenticating..." : biometricButtonTitle)
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 40)
                .padding(.vertical, 16)
                .background(Color.blue)
                .cornerRadius(12)
            }
            .disabled(isAuthenticating)
            
            Spacer()
        }
        .padding()
    }
    
    private var biometricIcon: String {
        switch biometricAuth.biometricType {
        case .touchID:
            return "touchid"
        case .faceID:
            return "faceid"
        case .none:
            return "lock.fill"
        }
    }
    
    private var biometricButtonTitle: String {
        switch biometricAuth.biometricType {
        case .touchID:
            return "Unlock with Touch ID"
        case .faceID:
            return "Unlock with Face ID"
        case .none:
            return "Unlock"
        }
    }
    
    private func authenticate() {
        isAuthenticating = true
        authError = nil
        
        Task {
            do {
                try await biometricAuth.authenticateAccess()
                await MainActor.run {
                    self.isAuthenticated = true
                    self.isAuthenticating = false
                }
            } catch {
                await MainActor.run {
                    self.authError = error.localizedDescription
                    self.isAuthenticating = false
                }
            }
        }
    }
}
