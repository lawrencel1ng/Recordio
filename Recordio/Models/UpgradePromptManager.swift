import Foundation

actor UpgradePromptManager {
    static let shared = UpgradePromptManager()
    
    private init() {}
    
    func shouldShowSpeakerUpgrade(recordings: [Recording]) async -> Bool {
        let currentTier = await AppState.shared.currentTier
        guard currentTier == .free else { return false }
        
        let recordingsWithMultipleSpeakers = recordings.filter { $0.detectedSpeakers > 1 }.count
        
        let hasSeenSpeakerUpgradePrompt = await AppState.shared.hasSeenSpeakerUpgradePrompt
        let speakerUpgradePromptCount = await AppState.shared.speakerUpgradePromptCount
        
        if recordingsWithMultipleSpeakers >= 3 && !hasSeenSpeakerUpgradePrompt {
            return true
        }
        
        if speakerUpgradePromptCount < 5 {
            if let lastDate = await AppState.shared.lastSpeakerPromptDate {
                let cooldown: TimeInterval = 3600 * 24 * 3
                if Date().timeIntervalSince(lastDate) > cooldown {
                    return true
                }
            } else {
                return true
            }
        }
        
        return false
    }
    
    func shouldShowProUpgrade(recordings: [Recording]) async -> Bool {
        let currentTier = await AppState.shared.currentTier
        guard currentTier == .speaker else { return false }
        
        let totalRecordings = recordings.count
        
        let hasSeenProUpgradePrompt = await AppState.shared.hasSeenProUpgradePrompt
        let proUpgradePromptCount = await AppState.shared.proUpgradePromptCount
        
        if totalRecordings >= 10 && !hasSeenProUpgradePrompt {
            return true
        }
        
        if proUpgradePromptCount < 3 {
            if let lastDate = await AppState.shared.lastProPromptDate {
                let cooldown: TimeInterval = 3600 * 24 * 7
                if Date().timeIntervalSince(lastDate) > cooldown {
                    return true
                }
            } else {
                return true
            }
        }
        
        return false
    }
    
    func shouldShowLifetimeUpgrade(recordings: [Recording], monthsSubscribed: Int) async -> Bool {
        let currentTier = await AppState.shared.currentTier
        guard currentTier == .pro || currentTier == .speaker else { return false }
        
        let hasSeenLifetimeUpgradePrompt = await AppState.shared.hasSeenLifetimeUpgradePrompt
        
        if monthsSubscribed >= 3 && !hasSeenLifetimeUpgradePrompt {
            return true
        }
        
        let lifetimeUpgradePromptCount = await AppState.shared.lifetimeUpgradePromptCount
        
        if recordings.count >= 50 && lifetimeUpgradePromptCount < 2 {
            if let lastDate = await AppState.shared.lastLifetimePromptDate {
                let cooldown: TimeInterval = 3600 * 24 * 30
                if Date().timeIntervalSince(lastDate) > cooldown {
                    return true
                }
            } else {
                return true
            }
        }
        
        return false
    }
    
    func markSpeakerPromptShown() async {
        await MainActor.run {
            AppState.shared.hasSeenSpeakerUpgradePrompt = true
            AppState.shared.speakerUpgradePromptCount += 1
            AppState.shared.lastSpeakerPromptDate = Date()
            AppState.shared.saveState()
        }
    }
    
    func markProPromptShown() async {
        await MainActor.run {
            AppState.shared.hasSeenProUpgradePrompt = true
            AppState.shared.proUpgradePromptCount += 1
            AppState.shared.lastProPromptDate = Date()
            AppState.shared.saveState()
        }
    }
    
    func markLifetimePromptShown() async {
        await MainActor.run {
            AppState.shared.hasSeenLifetimeUpgradePrompt = true
            AppState.shared.lifetimeUpgradePromptCount += 1
            AppState.shared.lastLifetimePromptDate = Date()
            AppState.shared.saveState()
        }
    }
}

enum ProUpgradeTrigger {
    case noisyRecording
    case longTranscript
    case tenthRecording
    case manualExport
    case advancedAnalytics
}
