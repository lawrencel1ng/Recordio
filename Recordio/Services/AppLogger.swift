import Foundation
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseAnalytics)
import FirebaseAnalytics
#endif
#if canImport(FirebaseCrashlytics)
import FirebaseCrashlytics
#endif

class AppLogger {
    static let shared = AppLogger()
    
    private init() {}
    
    func configure() {
        #if canImport(FirebaseCore)
        FirebaseApp.configure()
        #else
        print("⚠️ [AppLogger] Firebase not imported. Logging is disabled.")
        #endif
    }
    
    // MARK: - Events
    
    func logEvent(_ name: String, parameters: [String: Any]? = nil) {
        #if canImport(FirebaseAnalytics)
        Analytics.logEvent(name, parameters: parameters)
        #endif
        
        #if DEBUG
        print("📊 [Analytics] \(name): \(parameters ?? [:])")
        #endif
    }
    
    // MARK: - Errors
    
    func logError(_ error: Error, additionalInfo: [String: Any]? = nil) {
        #if canImport(FirebaseCrashlytics)
        Crashlytics.crashlytics().record(error: error)
        
        if let info = additionalInfo {
            let nsError = error as NSError
            let customKeysAndValues = info.mapValues { "\($0)" }
            Crashlytics.crashlytics().setCustomKeysAndValues(customKeysAndValues)
        }
        #endif
        
        #if DEBUG
        print("🔴 [Error] \(error.localizedDescription) - Info: \(additionalInfo ?? [:])")
        #endif
    }
    
    func setUserID(_ userID: String) {
        #if canImport(FirebaseAnalytics)
        Analytics.setUserID(userID)
        #endif
        #if canImport(FirebaseCrashlytics)
        Crashlytics.crashlytics().setUserID(userID)
        #endif
    }
    
    func setCustomKey(_ key: String, value: Any) {
        #if canImport(FirebaseCrashlytics)
        Crashlytics.crashlytics().setCustomValue(value, forKey: key)
        #endif
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
