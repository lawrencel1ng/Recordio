import Foundation
import Combine

/// Manages speaker labels/names across recordings
/// Maps global speaker IDs to user-assigned names
class SpeakerLabelManager: ObservableObject {
    static let shared = SpeakerLabelManager()
    
    private let storageKey = "speaker_labels"
    
    @Published private(set) var labels: [Int: String] = [:]
    
    private init() {
        loadLabels()
    }
    
    // MARK: - Public API
    
    /// Get the display name for a speaker ID
    func getName(for speakerId: Int) -> String {
        return labels[speakerId] ?? "Speaker \(speakerId + 1)"
    }
    
    /// Set a custom name for a speaker ID
    func setName(_ name: String, for speakerId: Int) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            labels.removeValue(forKey: speakerId)
        } else {
            labels[speakerId] = trimmed
        }
        saveLabels()
        objectWillChange.send()
    }
    
    /// Check if speaker has a custom name
    func hasCustomName(for speakerId: Int) -> Bool {
        return labels[speakerId] != nil
    }
    
    /// Get all speakers with custom names
    func getAllLabeledSpeakers() -> [(id: Int, name: String)] {
        return labels.map { (id: $0.key, name: $0.value) }
            .sorted { $0.id < $1.id }
    }
    
    /// Remove a custom name (revert to default)
    func removeName(for speakerId: Int) {
        labels.removeValue(forKey: speakerId)
        saveLabels()
        objectWillChange.send()
    }
    
    /// Clear all custom labels
    func clearAllLabels() {
        labels.removeAll()
        saveLabels()
        objectWillChange.send()
    }
    
    // MARK: - Persistence
    
    private func loadLabels() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return
        }
        // Convert string keys back to Int
        for (key, value) in decoded {
            if let intKey = Int(key) {
                labels[intKey] = value
            }
        }
    }
    
    private func saveLabels() {
        // Convert Int keys to String for JSON serialization
        let stringKeyLabels = Dictionary(uniqueKeysWithValues: labels.map { (String($0.key), $0.value) })
        if let data = try? JSONEncoder().encode(stringKeyLabels) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
