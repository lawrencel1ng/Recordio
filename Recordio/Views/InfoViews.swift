import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Privacy Policy")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Last Updated: January 1, 2026")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Group {
                    Text("1. Overview")
                        .font(.headline)
                    Text("Recordio is designed with privacy as its core principle. We believe that your personal recordings belong to you and you alone. Ideally, your data should never leave your device unless you explicitly choose to share it.")
                    
                    Text("2. Data Collection")
                        .font(.headline)
                    Text("We do not collect, store, or transmit your audio recordings to our servers. All audio processing, including transcription and speaker identification, is performed locally on your device using Apple's Neural Engine and Core ML technologies.")
                    
                    Text("3. iCloud Backup")
                        .font(.headline)
                    Text("If you enable iCloud Backup, your recordings are encrypted and stored in your personal iCloud container. We do not have access to these files. You manage this data directly through your Apple ID.")
                    
                    Text("4. Analytics")
                        .font(.headline)
                    Text("We collect anonymous, aggregate usage data to help us improve the app (e.g., crash reports, feature usage). This data cannot be used to identify you or access your content.")
                }
                .font(.body)
                
                Spacer(minLength: 40)
            }
            .padding()
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TermsOfServiceView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Terms of Service")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Last Updated: January 1, 2026")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Group {
                    Text("1. Acceptance of Terms")
                        .font(.headline)
                    Text("By downloading or using Recordio, you agree to these terms. If you do not agree, please do not use the app.")
                    
                    Text("2. Usage License")
                        .font(.headline)
                    Text("Recordio grants you a personal, non-transferable license to use the app for your personal or internal business purposes.")
                    
                    Text("3. Subscriptions")
                        .font(.headline)
                    Text("Some features require a paid subscription. Subscriptions automatically renew unless canceled at least 24 hours before the end of the current period. You can manage subscriptions in your Apple ID settings.")
                    
                    Text("4. Prohibited Uses")
                        .font(.headline)
                    Text("You may not use Recordio to record others without their consent where prohibited by law. It is your responsibility to comply with all local laws regarding audio recording.")
                    
                    Text("5. Disclaimer")
                        .font(.headline)
                    Text("Recordio is provided 'as is' without warranties of any kind. We are not responsible for any data loss or damages arising from your use of the app.")
                }
                .font(.body)
                
                Spacer(minLength: 40)
            }
            .padding()
        }
        .navigationTitle("Terms of Service")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SupportView: View {
    @Environment(\.openURL) var openURL
    
    var body: some View {
        Form {
            Section {
                VStack(spacing: 20) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                        .padding(.top)
                    
                    Text("Need Help?")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("We're here to help you get the most out of Recordio. Check our FAQ or send us a message.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            
            Section {
                Button(action: {
                    if let url = URL(string: "mailto:support@recordio.app") {
                        openURL(url)
                    }
                }) {
                    Label("Email Support", systemImage: "envelope")
                }
                
                Button(action: {
                    if let url = URL(string: "https://twitter.com/recordioapp") {
                        openURL(url)
                    }
                }) {
                    Label("Follow us on Twitter", systemImage: "bird")
                }
                
                Button(action: {
                    if let url = URL(string: "https://recordio.app/faq") {
                        openURL(url)
                    }
                }) {
                    Label("Frequently Asked Questions", systemImage: "questionmark.circle")
                }
            } header: {
                Text("Contact Us")
            }
            
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("App Version")
                        .font(.headline)
                    Text("1.0.0 (Build 1)")
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Device")
                        .font(.headline)
                    Text(UIDevice.current.model + " " + UIDevice.current.systemName + " " + UIDevice.current.systemVersion)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Diagnostics")
            }
        }
        .navigationTitle("Support")
        .navigationBarTitleDisplayMode(.inline)
    }
}
