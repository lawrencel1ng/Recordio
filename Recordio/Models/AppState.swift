import Foundation
import Combine
import CoreData

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()
    
    @Published var currentTier: SubscriptionTier = .free
    @Published var hasSeenOnboarding = false
    @Published var hasSeenSpeakerUpgradePrompt = false
    @Published var hasSeenProUpgradePrompt = false
    @Published var hasSeenLifetimeUpgradePrompt = false
    @Published var speakerUpgradePromptCount = 0
    @Published var proUpgradePromptCount = 0
    @Published var lifetimeUpgradePromptCount = 0
    @Published var lastSpeakerPromptDate: Date?
    @Published var lastProPromptDate: Date?
    @Published var lastLifetimePromptDate: Date?
    
    private let userDefaults = UserDefaults.standard
    
    private init() {
        loadState()
    }
    
    private func loadState() {
        if let tierString = userDefaults.string(forKey: "currentTier"),
           let tier = SubscriptionTier(rawValue: tierString) {
            currentTier = tier
        }
        
        hasSeenOnboarding = userDefaults.bool(forKey: "hasSeenOnboarding")
        hasSeenSpeakerUpgradePrompt = userDefaults.bool(forKey: "hasSeenSpeakerUpgradePrompt")
        hasSeenProUpgradePrompt = userDefaults.bool(forKey: "hasSeenProUpgradePrompt")
        hasSeenLifetimeUpgradePrompt = userDefaults.bool(forKey: "hasSeenLifetimeUpgradePrompt")
        
        speakerUpgradePromptCount = userDefaults.integer(forKey: "speakerUpgradePromptCount")
        proUpgradePromptCount = userDefaults.integer(forKey: "proUpgradePromptCount")
        lifetimeUpgradePromptCount = userDefaults.integer(forKey: "lifetimeUpgradePromptCount")
        
        lastSpeakerPromptDate = userDefaults.object(forKey: "lastSpeakerPromptDate") as? Date
        lastProPromptDate = userDefaults.object(forKey: "lastProPromptDate") as? Date
        lastLifetimePromptDate = userDefaults.object(forKey: "lastLifetimePromptDate") as? Date
    }
    
    func saveState() {
        userDefaults.set(currentTier.rawValue, forKey: "currentTier")
        userDefaults.set(hasSeenOnboarding, forKey: "hasSeenOnboarding")
        userDefaults.set(hasSeenSpeakerUpgradePrompt, forKey: "hasSeenSpeakerUpgradePrompt")
        userDefaults.set(hasSeenProUpgradePrompt, forKey: "hasSeenProUpgradePrompt")
        userDefaults.set(hasSeenLifetimeUpgradePrompt, forKey: "hasSeenLifetimeUpgradePrompt")
        
        userDefaults.set(speakerUpgradePromptCount, forKey: "speakerUpgradePromptCount")
        userDefaults.set(proUpgradePromptCount, forKey: "proUpgradePromptCount")
        userDefaults.set(lifetimeUpgradePromptCount, forKey: "lifetimeUpgradePromptCount")
        
        userDefaults.set(lastSpeakerPromptDate, forKey: "lastSpeakerPromptDate")
        userDefaults.set(lastProPromptDate, forKey: "lastProPromptDate")
        userDefaults.set(lastLifetimePromptDate, forKey: "lastLifetimePromptDate")
    }
    
    func upgrade(to tier: SubscriptionTier) {
        currentTier = tier
        saveState()
    }
    
    func canAccess(feature: Feature) -> Bool {
        switch feature {
        case .speakerDiarization:
            return currentTier != .free
        case .aiNoiseReduction:
            return currentTier == .pro || currentTier == .lifetime
        case .aiSummaries:
            return currentTier == .pro || currentTier == .lifetime
        case .audioEnhancement:
            return currentTier == .pro || currentTier == .lifetime
        case .exportSpeakerTracks:
            return currentTier == .pro || currentTier == .lifetime
        case .advancedSpeakerDiarization:
            return currentTier == .lifetime
        }
    }
}

enum Feature {
    case speakerDiarization
    case aiNoiseReduction
    case aiSummaries
    case audioEnhancement
    case exportSpeakerTracks
    case advancedSpeakerDiarization
}
