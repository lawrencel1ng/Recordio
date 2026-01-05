import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var biometricAuth = BiometricAuthService.shared
    
    // Persistent settings using @AppStorage
    @AppStorage("autoEnhanceAudio") private var autoEnhanceAudio = false
    @AppStorage("autoReduceNoise") private var autoReduceNoise = false
    @AppStorage("autoTranscribe") private var autoTranscribe = true
    @AppStorage("speakerIdentification") private var speakerIdentification = true
    @State private var isTogglingBiometric = false
    @State private var biometricError: String?
    @State private var showingBiometricError = false
    @StateObject private var cloudBackup = CloudBackupService.shared
    @State private var isTogglingBackup = false
    @State private var showingBackupError = false
    
    var body: some View {
        NavigationView {
            Form {
                subscriptionSection
                cloudBackupSection
                securitySection
                recordingSection
                transcriptionSection
                aboutSection
            }
            .navigationTitle("Settings")
        }
        .alert("Biometric Error", isPresented: $showingBiometricError) {
            Button("OK", role: .cancel) {}
        } message: {
            if let error = biometricError {
                Text(error)
            }
        }
        .alert("Backup Error", isPresented: $showingBackupError) {
            Button("OK", role: .cancel) {}
        } message: {
            if let error = cloudBackup.error?.errorDescription {
                Text(error)
            }
        }
    }
    
    private var subscriptionSection: some View {
        Section {
            VStack(spacing: 0) {
                // Premium subscription card
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: appState.currentTier == .lifetime ? [.purple, .pink] :
                                            appState.currentTier == .pro ? [.orange, .red] :
                                            appState.currentTier == .speaker ? [.blue, .cyan] : [.gray, .gray.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 56, height: 56)
                        
                        Image(systemName: appState.currentTier == .free ? "person.fill" : "crown.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(appState.currentTier.displayName)
                            .font(.headline)
                            .fontWeight(.bold)
                        
                        if let monthlyPrice = appState.currentTier.monthlyPrice, monthlyPrice > 0 {
                            Text(appState.currentTier.formattedMonthlyPrice + "/month")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else if appState.currentTier == .lifetime {
                            Text("Lifetime Access")
                                .font(.subheadline)
                                .foregroundColor(.green)
                        } else {
                            Text("Basic features")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    if appState.currentTier != .lifetime {
                        NavigationLink {
                            SubscriptionPlanView()
                        } label: {
                            Text("Upgrade")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                                )
                                .cornerRadius(20)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            
            if appState.currentTier != .lifetime {
                NavigationLink {
                    SubscriptionPlanView()
                } label: {
                    SettingsRow(
                        icon: "list.bullet.rectangle",
                        iconColor: .blue,
                        title: "View All Plans"
                    )
                }
            }
        } header: {
            Text("Subscription")
        }
    }
    
    private var securitySection: some View {
        Section {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: biometricAuth.isBiometricEnabled ? "lock.fill" : "lock.open.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Biometric Lock")
                        .font(.body)
                    
                    if biometricAuth.isBiometricEnabled {
                        Text("Require \(biometricAuth.biometricName) to open app")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Add an extra layer of security")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if isTogglingBiometric {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                } else {
                    Toggle("", isOn: Binding(
                        get: { biometricAuth.isBiometricEnabled },
                        set: { _ in toggleBiometricLock() }
                    ))
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Security")
        } footer: {
            if biometricAuth.biometricType == .none {
                Text("Biometric authentication is not available on this device")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }
    
    private func toggleBiometricLock() {
        isTogglingBiometric = true
        
        Task {
            do {
                try await biometricAuth.toggleBiometricLock()
                await MainActor.run {
                    isTogglingBiometric = false
                }
            } catch {
                await MainActor.run {
                    isTogglingBiometric = false
                    biometricError = error.localizedDescription
                    showingBiometricError = true
                }
            }
        }
    }
    
    private var cloudBackupSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .frame(width: 32, height: 32)
                        
                        Image(systemName: "icloud.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("iCloud Backup")
                            .font(.body)
                        
                        if cloudBackup.isBackupEnabled {
                            if let lastDate = cloudBackup.lastBackupDate {
                                Text("Last backup: \(lastDate, style: .relative)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("Backup enabled")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text("Securely backup your recordings")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    if isTogglingBackup {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    } else {
                        Toggle("", isOn: Binding(
                            get: { cloudBackup.isBackupEnabled },
                            set: { _ in toggleBackup() }
                        ))
                        .disabled(!cloudBackup.isAvailable)
                    }
                }
                .padding(.vertical, 4)
                
                if cloudBackup.isBackupEnabled {
                    Divider()
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Backup Size")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if let size = cloudBackup.backupSize {
                                Text(size)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            } else {
                                Text("Calculating...")
                                    .font(.subheadline)
                            }
                        }
                        
                        Spacer()
                        
                        Button(action: { Task { await cloudBackup.performBackup() } }) {
                            Label("Backup Now", systemImage: "arrow.clockwise")
                        }
                        .disabled(cloudBackup.isBackupInProgress)
                        .buttonStyle(.borderedProminent)
                    }
                    
                    if cloudBackup.isBackupInProgress {
                        HStack {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                            
                            Text("Backing up...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("Cloud Backup")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Recordings are encrypted before uploading to iCloud.")
                    .font(.caption)
                
                if let recovery = cloudBackup.error?.recoverySuggestion {
                    Text(recovery)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                
                if !cloudBackup.isAvailable {
                    Text("iCloud is not available on this device")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private func toggleBackup() {
        isTogglingBackup = true
        
        Task {
            await cloudBackup.toggleBackup()
            
            await MainActor.run {
                isTogglingBackup = false
                if cloudBackup.error != nil {
                    showingBackupError = true
                }
            }
        }
    }
    
    private var recordingSection: some View {
        Section {
            SettingsRow(
                icon: "waveform",
                iconColor: .purple,
                title: "Audio Quality",
                value: "48kHz / 24-bit"
            )
            
            SettingsRow(
                icon: "doc.fill",
                iconColor: .orange,
                title: "Audio Format",
                value: "WAV"
            )
            
            SettingsToggleRow(
                icon: "wand.and.stars",
                iconColor: .pink,
                title: "Auto-Enhance Audio",
                isOn: $autoEnhanceAudio,
                isDisabled: !appState.canAccess(feature: .audioEnhancement)
            )
            
            SettingsToggleRow(
                icon: "speaker.wave.3.fill",
                iconColor: .green,
                title: "Auto-Reduce Noise",
                isOn: $autoReduceNoise,
                isDisabled: !appState.canAccess(feature: .aiNoiseReduction)
            )
        } header: {
            Text("Recording")
        } footer: {
            if appState.currentTier == .free {
                Text("Upgrade to Pro to unlock audio enhancement features")
                    .font(.caption)
            } else if autoEnhanceAudio || autoReduceNoise {
                Text("Audio processing will be applied after recording")
                    .font(.caption)
            }
        }
    }
    
    private var transcriptionSection: some View {
        Section {
            SettingsToggleRow(
                icon: "text.bubble.fill",
                iconColor: .blue,
                title: "Auto-Transcribe",
                isOn: $autoTranscribe,
                isDisabled: false
            )
            
            SettingsToggleRow(
                icon: "person.2.fill",
                iconColor: .cyan,
                title: "Speaker Identification",
                isOn: $speakerIdentification,
                isDisabled: !appState.canAccess(feature: .speakerDiarization)
            )
            
            NavigationLink {
                AdvancedSettingsView()
            } label: {
                SettingsRow(
                    icon: "slider.horizontal.3",
                    iconColor: .gray,
                    title: "Advanced"
                )
            }
        } header: {
            Text("Transcription")
        } footer: {
            if appState.currentTier == .free && speakerIdentification {
                Text("Speaker identification requires Speaker tier")
            }
        }
    }
    
    private var aboutSection: some View {
        Section {
            SettingsRow(
                icon: "info.circle.fill",
                iconColor: .blue,
                title: "Version",
                value: "1.0.0"
            )
            
            NavigationLink {
                PrivacyPolicyView()
            } label: {
                SettingsRow(
                    icon: "hand.raised.fill",
                    iconColor: .blue,
                    title: "Privacy Policy"
                )
            }
            
            NavigationLink {
                TermsOfServiceView()
            } label: {
                SettingsRow(
                    icon: "doc.text.fill",
                    iconColor: .gray,
                    title: "Terms of Service"
                )
            }
            
            NavigationLink {
                SupportView()
            } label: {
                SettingsRow(
                    icon: "questionmark.circle.fill",
                    iconColor: .green,
                    title: "Support"
                )
            }
        } header: {
            Text("About")
        }
    }
}

// MARK: - Reusable Settings Row Components

struct SettingsRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    var value: String? = nil
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconColor.gradient)
                    .frame(width: 32, height: 32)
                
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            Text(title)
                .font(.body)
            
            Spacer()
            
            if let value = value {
                Text(value)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct SettingsToggleRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    @Binding var isOn: Bool
    var isDisabled: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconColor.gradient)
                    .frame(width: 32, height: 32)
                
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            Toggle(title, isOn: $isOn)
                .disabled(isDisabled)
                .onChange(of: isOn) { _, _ in
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                }
        }
        .opacity(isDisabled ? 0.6 : 1.0)
    }
}

// MARK: - Subscription Plan View

struct SubscriptionPlanView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    
    @State private var selectedPlan: SubscriptionTier = .free
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Text("Choose Your Plan")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Unlock powerful features")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top)
                
                // Plan cards
                VStack(spacing: 16) {
                    ForEach(SubscriptionTier.allCases, id: \.self) { tier in
                        PremiumPlanCard(
                            tier: tier,
                            isSelected: selectedPlan == tier,
                            isCurrent: appState.currentTier == tier,
                            isRecommended: tier == .pro,
                            onTap: {
                                withAnimation(.spring(response: 0.3)) {
                                    selectedPlan = tier
                                }
                                let generator = UIImpactFeedbackGenerator(style: .medium)
                                generator.impactOccurred()
                            }
                        )
                    }
                }
                .padding(.horizontal)
                
                // Subscribe button
                Button(action: subscribe) {
                    HStack {
                        Text(selectedPlan == appState.currentTier ? "Current Plan" : "Subscribe to \(selectedPlan.displayName)")
                            .font(.headline)
                        
                        if selectedPlan != appState.currentTier {
                            Image(systemName: "arrow.right")
                                .font(.headline)
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        Group {
                            if selectedPlan == appState.currentTier {
                                Color.gray
                            } else {
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            }
                        }
                    )
                    .cornerRadius(16)
                }
                .disabled(selectedPlan == appState.currentTier)
                .padding(.horizontal)
                
                // Footer text
                Text("Cancel anytime • Restore purchases")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom)
            }
        }
        .navigationTitle("Plans")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selectedPlan = appState.currentTier
        }
    }
    
    private func subscribe() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        appState.upgrade(to: selectedPlan)
        dismiss()
    }
}

// MARK: - Premium Plan Card

struct PremiumPlanCard: View {
    let tier: SubscriptionTier
    let isSelected: Bool
    let isCurrent: Bool
    let isRecommended: Bool
    let onTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header row
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(tier.displayName)
                            .font(.title3)
                            .fontWeight(.bold)
                        
                        if isCurrent {
                            Text("Current")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green)
                                .cornerRadius(8)
                        }
                        
                        if isRecommended && !isCurrent {
                            Text("Popular")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    LinearGradient(colors: [.orange, .pink], startPoint: .leading, endPoint: .trailing)
                                )
                                .cornerRadius(8)
                        }
                    }
                    
                    // Price
                    Group {
                        if let monthlyPrice = tier.monthlyPrice, monthlyPrice > 0 {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(tier.formattedMonthlyPrice)
                                    .font(.title)
                                    .fontWeight(.bold)
                                Text("/month")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        } else if tier.lifetimePrice != nil {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(tier.formattedLifetimePrice)
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundStyle(
                                        LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing)
                                    )
                                Text("one-time")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text("Free")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.green)
                        }
                    }
                }
                
                Spacer()
                
                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: 2)
                        .frame(width: 28, height: 28)
                    
                    if isSelected {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 20, height: 20)
                        
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            
            Divider()
            
            // Features list
            VStack(alignment: .leading, spacing: 10) {
                ForEach(tier.features, id: \.self) { feature in
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(
                                LinearGradient(colors: [.green, .mint], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                        
                        Text(feature)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isSelected ? Color.blue.opacity(0.08) : Color(.systemBackground))
                .shadow(color: isSelected ? .blue.opacity(0.2) : .black.opacity(0.05), radius: isSelected ? 12 : 6, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    isSelected ? 
                        LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing) :
                        LinearGradient(colors: [Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: isSelected ? 2 : 0
                )
        )
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.3), value: isSelected)
        .onTapGesture {
            onTap()
        }
    }
}
