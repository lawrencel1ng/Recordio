import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    
    @State private var currentPage = 0
    
    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "waveform.circle.fill",
            title: "Studio-Quality Recording",
            description: "Record in crystal clear 48kHz/24-bit audio quality. Professional grade recording in your pocket."
        ),
        OnboardingPage(
            icon: "person.2.wave.2.fill",
            title: "Speaker Identification",
            description: "Automatically identify and separate different speakers. Know exactly who said what."
        ),
        OnboardingPage(
            icon: "sparkles",
            title: "AI-Powered Features",
            description: "Transcribe audio instantly, get AI summaries, and enhance audio quality - all offline."
        ),
        OnboardingPage(
            icon: "lock.shield.fill",
            title: "100% Private & Offline",
            description: "All processing happens on your device. Your recordings never leave your phone."
        )
    ]
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                HStack {
                    if currentPage > 0 {
                        Button(action: { currentPage -= 1 }) {
                            Image(systemName: "chevron.left")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                    } else {
                        Color.clear
                            .frame(width: 44)
                    }
                    
                    Spacer()
                    
                    Button("Skip") {
                        completeOnboarding()
                    }
                    .foregroundColor(.blue)
                    .fontWeight(.semibold)
                    
                    Color.clear
                        .frame(width: 44)
                }
                .padding()
                
                Spacer()
                
                TabView(selection: $currentPage) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        OnboardingPageView(page: pages[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 500)
                
                Spacer()
                
                pageIndicator
                
                continueButton
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)
            }
        }
    }
    
    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<pages.count, id: \.self) { index in
                Circle()
                    .fill(index == currentPage ? Color.blue : Color.gray)
                    .frame(width: index == currentPage ? 24 : 8, height: 8)
                    .animation(.spring(), value: currentPage)
            }
        }
        .padding(.bottom, 20)
    }
    
    private var continueButton: some View {
        Button(action: {
            if currentPage < pages.count - 1 {
                withAnimation {
                    currentPage += 1
                }
            } else {
                completeOnboarding()
            }
        }) {
            Text(currentPage == pages.count - 1 ? "Get Started" : "Continue")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .cornerRadius(12)
        }
    }
    
    private func completeOnboarding() {
        appState.hasSeenOnboarding = true
        appState.saveState()
        isPresented = false
    }
}

struct OnboardingPageView: View {
    let page: OnboardingPage
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: page.icon)
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            Text(page.title)
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .foregroundColor(.white)
            
            Text(page.description)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)
            
            if page.title.contains("Private") {
                PrivacyBadge()
                    .padding(.top, -10)
            }
        }
        .padding()
    }
}

struct OnboardingPage {
    let icon: String
    let title: String
    let description: String
}
