import SwiftUI

struct SpeakerUpgradePrompt: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    
    @State private var isProcessing = false
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2.wave.2.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("Know Who Said What")
                .font(.title.bold())
            
            Text("You've recorded meetings with multiple speakers. Upgrade to automatically identify and label each person.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "person.fill.checkmark", text: "Real-time speaker identification")
                FeatureRow(icon: "paintpalette.fill", text: "Color-coded speakers")
                FeatureRow(icon: "chart.bar.fill", text: "Speaker statistics & analytics")
                FeatureRow(icon: "arrow.triangle.branch", text: "Export individual speaker tracks")
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            
            VStack(spacing: 12) {
                Button(action: startTrial) {
                    HStack {
                        Text("Start 7-Day Free Trial")
                            .fontWeight(.semibold)
                        Image(systemName: "arrow.right")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(isProcessing)
                
                Text("Then $2.99/month • Cancel anytime")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button("Maybe Later") {
                    dismiss()
                }
                .font(.subheadline)
                .foregroundColor(.blue)
            }
        }
        .padding(24)
    }
    
    private func startTrial() {
        isProcessing = true
        appState.upgrade(to: .speaker)
        dismiss()
    }
}

struct ProUpgradePrompt: View {
    let trigger: ProUpgradeTrigger
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    
    @State private var isProcessing = false
    
    var body: some View {
        VStack(spacing: 20) {
            switch trigger {
            case .noisyRecording:
                noiseReductionPitch
            case .longTranscript:
                summaryPitch
            case .tenthRecording:
                timeValuePitch
            case .manualExport:
                exportPitch
            case .advancedAnalytics:
                analyticsPitch
            }
            
            VStack(spacing: 12) {
                Button(action: startProTrial) {
                    VStack(spacing: 4) {
                        Text("Upgrade to Pro")
                            .font(.headline)
                        Text("Just $2 more/month")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(isProcessing)
                
                Text("Try free for 14 days • $4.99/mo after")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button("Maybe Later") {
                    dismiss()
                }
                .font(.subheadline)
                .foregroundColor(.orange)
            }
        }
        .padding(24)
    }
    
    var noiseReductionPitch: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.badge.minus")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            Text("Background Noise Detected")
                .font(.title2.bold())
            
            Text("We noticed background noise in your last recording. Pro unlocks AI-powered noise reduction for crystal clear audio.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
    }
    
    var summaryPitch: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            Text("Save Time with AI Summaries")
                .font(.title2.bold())
            
            Text("This meeting generated a long transcript. Pro can summarize it to key points in 30 seconds.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
    }
    
    var timeValuePitch: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            Text("You're a Power User! 🎉")
                .font(.title2.bold())
            
            Text("You've recorded 10 times. Upgrade to Pro to unlock AI features and save hours of work.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
    }
    
    var exportPitch: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.and.arrow.up.on.square")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            Text("Export Individual Speakers")
                .font(.title2.bold())
            
            Text("Export each speaker's audio separately for professional editing and post-production.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
    }
    
    var analyticsPitch: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            Text("Unlock Advanced Analytics")
                .font(.title2.bold())
            
            Text("Get deep insights into your recordings with speaker analysis, word frequency, engagement metrics, and more.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
    }
    
    private func startProTrial() {
        isProcessing = true
        appState.upgrade(to: .pro)
        dismiss()
    }
}

struct LifetimeUpgradePrompt: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    
    @State private var monthsSubscribed = 3
    @State private var isProcessing = false
    
    var totalSpent: Decimal {
        Decimal(monthsSubscribed) * 4.99
    }
    
    var savingsOver3Years: Decimal {
        (4.99 * 36) - 79.99
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "infinity.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.purple)
            
            Text("You Love Our App! 🎉")
                .font(.title.bold())
            
            Text("You've been a Pro member for \(monthsSubscribed) months and paid $\(totalSpent). Lock in lifetime access and never pay again.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            HStack(spacing: 20) {
                VStack {
                    Text("3 Years Pro")
                        .font(.caption)
                    Text("$179.64")
                        .font(.title2.bold())
                        .strikethrough()
                }
                
                Image(systemName: "arrow.right")
                
                VStack {
                    Text("Lifetime")
                        .font(.caption)
                    Text("$79.99")
                        .font(.title.bold())
                        .foregroundColor(.green)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            
            Text("Save $\(savingsOver3Years)")
                .font(.headline)
                .foregroundColor(.green)
            
            Button(action: purchaseLifetime) {
                Text("Get Lifetime Access - $79.99")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .disabled(isProcessing)
            
            VStack(spacing: 4) {
                Text("⚡️ Early Adopter Price")
                    .font(.caption.bold())
                Text("Price increases to $99.99 in 30 days")
                    .font(.caption)
            }
            .foregroundColor(.orange)
        }
        .padding(24)
    }
    
    private func purchaseLifetime() {
        isProcessing = true
        appState.upgrade(to: .lifetime)
        dismiss()
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            Text(text)
                .font(.subheadline)
        }
    }
}

struct UpgradePromptView: View {
    let promptType: RecordingsListView.UpgradePromptType
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            switch promptType {
            case .speaker:
                SpeakerUpgradePrompt()
            case .pro:
                ProUpgradePrompt(trigger: .tenthRecording)
            case .lifetime:
                LifetimeUpgradePrompt()
            }
        }
        .navigationBarHidden(true)
    }
}
