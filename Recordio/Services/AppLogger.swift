import Foundation
import FirebaseCore
import FirebaseAnalytics
import FirebaseCrashlytics

class AppLogger {
    static let shared = AppLogger()
    
    private init() {}
    
    func configure() {
        FirebaseApp.configure()
    }
    
    // MARK: - Events
    
    func logEvent(_ name: String, parameters: [String: Any]? = nil) {
        Analytics.logEvent(name, parameters: parameters)
        
        #if DEBUG
        print("📊 [Analytics] \(name): \(parameters ?? [:])")
        #endif
    }
    
    // MARK: - Errors
    
    func logError(_ error: Error, additionalInfo: [String: Any]? = nil) {
        Crashlytics.crashlytics().record(error: error)
        
        if let info = additionalInfo {
            let nsError = error as NSError
            let customKeysAndValues = info.mapValues { "\($0)" }
            Crashlytics.crashlytics().setCustomKeysAndValues(customKeysAndValues)
        }
        
        #if DEBUG
        print("🔴 [Error] \(error.localizedDescription) - Info: \(additionalInfo ?? [:])")
        #endif
    }
    
    func setUserID(_ userID: String) {
        Analytics.setUserID(userID)
        Crashlytics.crashlytics().setUserID(userID)
    }
    
    func setCustomKey(_ key: String, value: Any) {
        Crashlytics.crashlytics().setCustomValue(value, forKey: key)
    }
}

// MARK: - Event Names
extension AppLogger {
    struct Events {
        static let appLaunch = "app_launch"
        static let recordingStarted = "recording_started"
        static let recordingStopped = "recording_stopped"
        static let recordingDeleted = "recording_deleted"
        static let transcriptionStarted = "transcription_started"
        static let transcriptionCompleted = "transcription_completed"
        static let transcriptionFailed = "transcription_failed"
        static let backupStarted = "backup_started"
        static let backupCompleted = "backup_completed"
        static let backupFailed = "backup_failed"
        static let exportStarted = "export_started"
        static let exportCompleted = "export_completed"
        static let purchaseAttempt = "purchase_attempt"
        static let purchaseSuccess = "purchase_success"
        static let purchaseFailed = "purchase_failed"
    }
    
    struct Params {
        static let duration = "duration"
        static let wordCount = "word_count"
        static let errorDescription = "error_description"
        static let fileFormat = "file_format"
        static let cloudProvider = "cloud_provider"
        static let productID = "product_id"
    }
}
