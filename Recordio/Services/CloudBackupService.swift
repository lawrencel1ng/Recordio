import Foundation
import CloudKit
import CryptoKit
import Combine
import AVFoundation

class CloudBackupService: ObservableObject {
    static let shared = CloudBackupService()
    
    @Published var isBackupEnabled = false
    @Published var isBackupInProgress = false
    @Published var lastBackupDate: Date?
    @Published var backupSize: String?
    @Published var error: CloudBackupError?
    @Published var isAvailable: Bool = false
    @Published var selectedProviderType: BackupProviderType = .iCloud
    @Published var scheduledBackupEnabled: Bool = false
    @Published var scheduledHour: Int = 3
    @Published var scheduledMinute: Int = 0
    
    private lazy var container = CKContainer(identifier: "iCloud.com.recordio")
    private lazy var database = container.privateCloudDatabase
    
    private let keychainKey = "com.recordio.encryption.key"
    private let providerKey = "com.recordio.backup.provider"
    private let scheduledKey = "com.recordio.backup.scheduled"
    private let scheduledHourKey = "com.recordio.backup.scheduled.hour"
    private let scheduledMinuteKey = "com.recordio.backup.scheduled.minute"
    private var scheduleTimer: Timer?
    private var lastScheduledRun: Date?
    
    private init() {
        loadBackupSettings()
        Task { await refreshAvailability() }
    }
    
    private var _cachedProvider: CloudProvider?
    
    private var provider: CloudProvider {
        if let cached = _cachedProvider, cached.name == selectedProviderType.displayName {
            return cached
        }
        let newProvider: CloudProvider
        switch selectedProviderType {
        case .iCloud:
            newProvider = ICloudProvider(container: container, database: database)
        case .googleDrive:
            newProvider = GoogleDriveProvider()
        case .dropbox:
            newProvider = DropboxProvider()
        case .box:
            newProvider = BoxProvider()
        case .oneDrive:
            newProvider = OneDriveProvider()
        }
        _cachedProvider = newProvider
        return newProvider
    }
    
    private var encryptionKey: SymmetricKey? {
        get {
            guard let keyData = KeychainHelper.shared.load(key: keychainKey) else {
                return nil
            }
            return SymmetricKey(data: keyData)
        }
        set {
            if let keyData = newValue?.withUnsafeBytes({ Data($0) }) {
                KeychainHelper.shared.save(key: keychainKey, data: keyData)
            }
        }
    }
    
    func generateEncryptionKey() {
        let key = SymmetricKey(size: .bits256)
        encryptionKey = key
    }
    
    func loadBackupSettings() {
        let userDefaults = UserDefaults.standard
        isBackupEnabled = userDefaults.bool(forKey: "icloudBackupEnabled")
        if let timestamp = userDefaults.object(forKey: "lastBackupDate") as? Date {
            lastBackupDate = timestamp
        }
        if let size = userDefaults.string(forKey: "backupSize") {
            backupSize = size
        }
        if let raw = userDefaults.string(forKey: providerKey), let t = BackupProviderType(rawValue: raw) {
            selectedProviderType = t
        }
        scheduledBackupEnabled = userDefaults.bool(forKey: scheduledKey)
        let hour = userDefaults.integer(forKey: scheduledHourKey)
        let minute = userDefaults.integer(forKey: scheduledMinuteKey)
        if hour >= 0 && hour < 24 { scheduledHour = hour }
        if minute >= 0 && minute < 60 { scheduledMinute = minute }
        if scheduledBackupEnabled { startSchedule() }
    }
    
    func saveBackupSettings() {
        let userDefaults = UserDefaults.standard
        userDefaults.set(isBackupEnabled, forKey: "icloudBackupEnabled")
        if let date = lastBackupDate {
            userDefaults.set(date, forKey: "lastBackupDate")
        }
        if let size = backupSize {
            userDefaults.set(size, forKey: "backupSize")
        }
        userDefaults.set(selectedProviderType.rawValue, forKey: providerKey)
        userDefaults.set(scheduledBackupEnabled, forKey: scheduledKey)
        userDefaults.set(scheduledHour, forKey: scheduledHourKey)
        userDefaults.set(scheduledMinute, forKey: scheduledMinuteKey)
    }
    
    func toggleBackup() async {
        guard isAvailable else {
            await MainActor.run {
                self.error = .accountUnavailable
            }
            return
        }
        
        if isBackupEnabled {
            await disableBackup()
        } else {
            await enableBackup()
        }
    }
    
    private func enableBackup() async {
        isBackupInProgress = true
        error = nil
        
        if selectedProviderType == .iCloud {
            await MainActor.run {
                self.error = .accountUnavailable
                self.isBackupInProgress = false
            }
            return
        }
        
        if encryptionKey == nil {
            generateEncryptionKey()
        }
        
        do {
            try await provider.authorize()
            let available = await provider.isAvailable()
            if available {
                isBackupEnabled = true
                saveBackupSettings()
                await MainActor.run { self.isBackupInProgress = false }
                await performBackup()
            } else {
                await MainActor.run {
                    self.error = .accountUnavailable
                    self.isBackupInProgress = false
                }
            }
        } catch {
            await MainActor.run {
                self.error = .backupFailed(error.localizedDescription)
                self.isBackupInProgress = false
            }
        }
    }
    
    private func disableBackup() async {
        isBackupInProgress = true
        
        do {
            let query = CKQuery(recordType: "RecordingRecord", predicate: NSPredicate(value: true))
            
            let recordIDs: [CKRecord.ID] = await withCheckedContinuation { continuation in
                let operation = CKQueryOperation(query: query)
                operation.desiredKeys = []
                var ids: [CKRecord.ID] = []
                
                operation.recordMatchedBlock = { recordID, _ in
                    ids.append(recordID)
                }
                
                operation.queryCompletionBlock = { _, error in
                    if let error = error {
                        print("Error fetching records for deletion: \(error)")
                        // If query fails, we can't delete anything
                        continuation.resume(returning: [])
                    } else {
                        continuation.resume(returning: ids)
                    }
                }
                
                database.add(operation)
            }
            
            if !recordIDs.isEmpty {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    let deleteOperation = CKModifyRecordsOperation(recordIDsToDelete: recordIDs)
                    deleteOperation.modifyRecordsCompletionBlock = { _, _, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: ())
                        }
                    }
                    database.add(deleteOperation)
                }
            }
            
            await MainActor.run {
                self.isBackupEnabled = false
                self.saveBackupSettings()
                self.isBackupInProgress = false
            }
        } catch {
            await MainActor.run {
                self.error = .backupFailed(error.localizedDescription)
                self.isBackupInProgress = false
            }
        }
    }
    
    func performBackup() async {
        guard isBackupEnabled else { return }
        guard isAvailable else {
            scheduleBackupRetry(reason: .accountUnavailable)
            return
        }
        
        isBackupInProgress = true
        error = nil
        
        AppLogger.shared.logEvent(AppLogger.Events.backupStarted, parameters: [
            AppLogger.Params.cloudProvider: selectedProviderType.displayName
        ])
        
        do {
            let recordings = try await fetchLocalRecordings()
            guard let key = encryptionKey else { throw CloudBackupError.encryptionKeyMissing }
            let totalSize = try await provider.backup(records: recordings, key: key)
            
            await MainActor.run {
                self.lastBackupDate = Date()
                self.backupSize = formatBytes(totalSize)
                self.saveBackupSettings()
                self.isBackupInProgress = false
                self.resetRetry()
            }
            
            AppLogger.shared.logEvent(AppLogger.Events.backupCompleted, parameters: [
                AppLogger.Params.cloudProvider: selectedProviderType.displayName,
                "size_bytes": totalSize
            ])
        } catch {
            AppLogger.shared.logEvent(AppLogger.Events.backupFailed, parameters: [
                AppLogger.Params.errorDescription: error.localizedDescription,
                AppLogger.Params.cloudProvider: selectedProviderType.displayName
            ])
            AppLogger.shared.logError(error, additionalInfo: ["context": "performBackup"])
            
            await MainActor.run {
                self.error = .backupFailed(error.localizedDescription)
                self.isBackupInProgress = false
            }
            scheduleBackupRetry(reason: .networkError)
        }
    }
    
    func restoreFromBackup() async throws {
        guard let key = encryptionKey else {
            throw CloudBackupError.encryptionKeyMissing
        }
        
        isBackupInProgress = true
        
        let records: [CKRecord] = await withCheckedContinuation { continuation in
            let query = CKQuery(recordType: "RecordingRecord", predicate: NSPredicate(value: true))
            let operation = CKQueryOperation(query: query)
            var fetched: [CKRecord] = []
            
            operation.recordMatchedBlock = { _, result in
                switch result {
                case .success(let record):
                    fetched.append(record)
                case .failure(let error):
                    print("Error fetching record: \(error)")
                }
            }
            
            operation.queryCompletionBlock = { _, error in
                if let error = error {
                    print("Restore query failed: \(error)")
                    continuation.resume(returning: [])
                } else {
                    continuation.resume(returning: fetched)
                }
            }
            
            database.add(operation)
        }
        
        for record in records {
            do {
                try await self.restoreRecording(from: record, using: key)
            } catch {
                await MainActor.run {
                    self.error = .restoreFailed(error.localizedDescription)
                }
            }
        }
        
        await MainActor.run {
            self.isBackupInProgress = false
        }
    }
    
    private func fetchLocalRecordings() async throws -> [LocalRecording] {
        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recordingsPath = documentsPath.appendingPathComponent("Recordings", isDirectory: true)
        
        guard let contents = try? fileManager.contentsOfDirectory(at: recordingsPath, includingPropertiesForKeys: [.fileSizeKey], options: []) else {
            return []
        }
        
        var recordings: [LocalRecording] = []
        
        for url in contents {
            guard url.pathExtension == "wav" || url.pathExtension == "m4a" else { continue }
            
            let attributes = try? fileManager.attributesOfItem(atPath: url.path)
            let fileSize = attributes?[.size] as? Int ?? 0
            let createdAt = attributes?[.creationDate] as? Date ?? Date()
            let filename = url.deletingPathExtension().lastPathComponent
            
            recordings.append(LocalRecording(id: UUID(), url: url, title: filename, createdAt: createdAt, fileSize: fileSize))
        }
        
        return recordings
    }
    
    private func restoreRecording(from record: CKRecord, using key: SymmetricKey) async throws {
        guard let asset = record["audioFile"] as? CKAsset,
              let fileURL = asset.fileURL else {
            throw CloudBackupError.invalidRecord
        }
        
        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recordingsPath = documentsPath.appendingPathComponent("Recordings", isDirectory: true)
        
        try fileManager.createDirectory(at: recordingsPath, withIntermediateDirectories: true)
        
        let encryptedData = try Data(contentsOf: fileURL)
        let decryptedData = try decryptData(encryptedData, using: key)
        
        let existing = try? FileManager.default.contentsOfDirectory(at: recordingsPath, includingPropertiesForKeys: nil)
        if let existing = existing {
            let newHash = SHA256.hash(data: decryptedData)
            let newHashString = Data(newHash).map { String(format: "%02hhx", $0) }.joined()
            for url in existing where url.pathExtension == "wav" || url.pathExtension == "m4a" {
                if let data = try? Data(contentsOf: url) {
                    let h = SHA256.hash(data: data)
                    let hs = Data(h).map { String(format: "%02hhx", $0) }.joined()
                    if hs == newHashString {
                        return
                    }
                }
            }
        }
        
        let filename = record["title"] as? String ?? "Restored Recording"
        let destinationURL = recordingsPath.appendingPathComponent("\(filename)_restored.m4a")
        
        try decryptedData.write(to: destinationURL)
        
        let avAsset = AVAsset(url: destinationURL)
        let duration = CMTimeGetSeconds(avAsset.duration)
        let title = (record["title"] as? String) ?? "Restored Recording"
        _ = RecordingManager.shared.createRecording(title: title, audioURL: destinationURL, duration: duration)
    }
    
    private func encryptData(_ data: Data, using key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.seal(data, using: key)
        guard let combinedData = sealedBox.combined else {
            throw CloudBackupError.encryptionFailed("Failed to encrypt data")
        }
        return Data(combinedData)
    }
    
    private func decryptData(_ data: Data, using key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return Data(try AES.GCM.open(sealedBox, using: key))
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    func checkCloudAvailability() async -> Bool {
        do {
            let status = try await container.accountStatus()
            return status == .available
        } catch {
            return false
        }
    }
    
    func refreshAvailability() async {
        if selectedProviderType == .iCloud {
            isAvailable = false
        } else {
            isAvailable = await provider.isAvailable()
        }
    }
    
    private var retryDelay: TimeInterval = 60
    private let maxRetryDelay: TimeInterval = 7200
    private var retryWorkItem: DispatchWorkItem?
    
    private func scheduleBackupRetry(reason: CloudBackupError) {
        guard isBackupEnabled, !isBackupInProgress else { return }
        error = reason
        retryWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            Task { await self.performBackup() }
        }
        retryWorkItem = workItem
        DispatchQueue.global().asyncAfter(deadline: .now() + retryDelay, execute: workItem)
        retryDelay = min(retryDelay * 2, maxRetryDelay)
    }
    
    private func resetRetry() {
        retryWorkItem?.cancel()
        retryWorkItem = nil
        retryDelay = 60
    }
    
    func setProvider(_ type: BackupProviderType) {
        selectedProviderType = type
        saveBackupSettings()
        Task { await refreshAvailability() }
    }

    func authorizeProvider() async {
        do {
            if selectedProviderType == .iCloud {
                await MainActor.run { self.isAvailable = false }
                return
            }
            try await provider.authorize()
            let available = await provider.isAvailable()
            await MainActor.run { self.isAvailable = available }
        } catch {
            await MainActor.run { self.error = .backupFailed(error.localizedDescription) }
        }
    }
    
    func exportRecoveryKey() throws -> URL {
        guard let key = encryptionKey else { throw CloudBackupError.encryptionKeyMissing }
        let data = key.withUnsafeBytes { Data($0) }
        let base64 = data.base64EncodedString()
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let outURL = documentsPath.appendingPathComponent("recordio_recovery.key")
        try base64.write(to: outURL, atomically: true, encoding: .utf8)
        return outURL
    }
    
    func setScheduledBackup(enabled: Bool, hour: Int, minute: Int) {
        scheduledBackupEnabled = enabled
        scheduledHour = max(0, min(23, hour))
        scheduledMinute = max(0, min(59, minute))
        saveBackupSettings()
        if enabled {
            startSchedule()
        } else {
            stopSchedule()
        }
    }
    
    struct LocalRecording {
        let id: UUID
        let url: URL
        let title: String?
        let createdAt: Date
        let fileSize: Int
    }
    
    private func startSchedule() {
        scheduleTimer?.invalidate()
        scheduleTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            guard self.scheduledBackupEnabled, !self.isBackupInProgress, self.isBackupEnabled else { return }
            let now = Date()
            let cal = Calendar.current
            let comps = cal.dateComponents([.hour, .minute], from: now)
            if comps.hour == self.scheduledHour && comps.minute == self.scheduledMinute {
                if let last = self.lastScheduledRun, cal.isDate(last, inSameDayAs: now) {
                    return
                }
                self.lastScheduledRun = now
                Task { await self.performBackup() }
            }
        }
    }
    
    private func stopSchedule() {
        scheduleTimer?.invalidate()
        scheduleTimer = nil
    }
}

enum CloudBackupError: Error, LocalizedError {
    case accountRestricted
    case accountUnavailable
    case backupFailed(String)
    case restoreFailed(String)
    case encryptionFailed(String)
    case decryptionFailed(String)
    case encryptionKeyMissing
    case invalidRecord
    case networkError
    case fileReadError
    
    var errorDescription: String? {
        switch self {
        case .accountRestricted:
            return "iCloud account is restricted"
        case .accountUnavailable:
            return "iCloud account is not available"
        case .backupFailed(let message):
            return "Backup failed: \(message)"
        case .restoreFailed(let message):
            return "Restore failed: \(message)"
        case .encryptionFailed(let message):
            return "Encryption failed: \(message)"
        case .decryptionFailed(let message):
            return "Decryption failed: \(message)"
        case .encryptionKeyMissing:
            return "Encryption key is missing"
        case .invalidRecord:
            return "Invalid backup record"
        case .networkError:
            return "Network error occurred"
        case .fileReadError:
            return "Failed to read audio file"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .accountUnavailable:
            return "Please sign in to iCloud in Settings"
        case .networkError:
            return "Please check your internet connection"
        default:
            return nil
        }
    }
}

enum BackupProviderType: String, CaseIterable {
    case iCloud
    case googleDrive
    case dropbox
    case box
    case oneDrive
    
    var displayName: String {
        switch self {
        case .iCloud: return "iCloud"
        case .googleDrive: return "Google Drive"
        case .dropbox: return "Dropbox"
        case .box: return "Box"
        case .oneDrive: return "OneDrive"
        }
    }
}

protocol CloudProvider {
    var name: String { get }
    func isAvailable() async -> Bool
    func authorize() async throws
    func backup(records: [CloudBackupService.LocalRecording], key: SymmetricKey) async throws -> Int
    func restore(key: SymmetricKey) async throws
}

struct UnsupportedProvider: CloudProvider {
    let name: String
    func isAvailable() async -> Bool { false }
    func authorize() async throws { throw CloudBackupError.accountUnavailable }
    func backup(records: [CloudBackupService.LocalRecording], key: SymmetricKey) async throws -> Int { throw CloudBackupError.accountUnavailable }
    func restore(key: SymmetricKey) async throws { throw CloudBackupError.accountUnavailable }
}

final class GoogleDriveProvider: CloudProvider {
    let name = "Google Drive"
    private let tokenKey = "com.recordio.gdrive.token"
    private let baseFolderName = "DriveBackups"
    
    func isAvailable() async -> Bool {
        return KeychainHelper.shared.load(key: tokenKey) != nil
    }
    
    func authorize() async throws {
        try await OAuthManager.shared.startAuthorization(for: .googleDrive)
    }
    
    func backup(records: [CloudBackupService.LocalRecording], key: SymmetricKey) async throws -> Int {
        guard let tokenData = KeychainHelper.shared.load(key: tokenKey),
              let accessToken = String(data: tokenData, encoding: .utf8) else {
            throw CloudBackupError.accountUnavailable
        }
        var totalSize = 0
        let session = URLSession.shared
        for r in records {
            guard let data = try? Data(contentsOf: r.url) else { continue }
            let hash = SHA256.hash(data: data)
            let hashString = Data(hash).map { String(format: "%02hhx", $0) }.joined()
            let name = "\(hashString).enc"
            var searchComps = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
            searchComps.queryItems = [
                URLQueryItem(name: "q", value: "name='\(name)'"),
                URLQueryItem(name: "fields", value: "files(id)")
            ]
            var searchReq = URLRequest(url: searchComps.url!)
            searchReq.httpMethod = "GET"
            searchReq.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            do {
                let (sData, sResp) = try await session.data(for: searchReq)
                if let http = sResp as? HTTPURLResponse, http.statusCode == 200 {
                    if let obj = try? JSONSerialization.jsonObject(with: sData) as? [String: Any],
                       let files = obj["files"] as? [[String: Any]],
                       !files.isEmpty {
                        continue
                    }
                }
            } catch {}
            let sealed = try AES.GCM.seal(data, using: key)
            guard let combined = sealed.combined else { continue }
            let boundary = "Boundary-\(UUID().uuidString)"
            var uploadReq = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart")!)
            uploadReq.httpMethod = "POST"
            uploadReq.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            uploadReq.addValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            let metadata: [String: Any] = [
                "name": name,
                "mimeType": "application/octet-stream"
            ]
            let metaData = try JSONSerialization.data(withJSONObject: metadata)
            var body = Data()
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Type: application/json; charset=UTF-8\r\n\r\n".utf8))
            body.append(metaData)
            body.append(Data("\r\n--\(boundary)\r\n".utf8))
            body.append(Data("Content-Type: application/octet-stream\r\n\r\n".utf8))
            body.append(Data(combined))
            body.append(Data("\r\n--\(boundary)--\r\n".utf8))
            uploadReq.httpBody = body
            let (_, uResp) = try await session.data(for: uploadReq)
            guard let http = uResp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw CloudBackupError.backupFailed("Google Drive upload failed")
            }
            totalSize += combined.count
        }
        return totalSize
    }
    
    func restore(key: SymmetricKey) async throws {}
}

final class DropboxProvider: CloudProvider {
    let name = "Dropbox"
    private let tokenKey = "com.recordio.dropbox.token"
    private let baseFolderName = "DropboxBackups"
    
    func isAvailable() async -> Bool {
        return KeychainHelper.shared.load(key: tokenKey) != nil
    }
    
    func authorize() async throws {
        try await OAuthManager.shared.startAuthorization(for: .dropbox)
    }
    
    func backup(records: [CloudBackupService.LocalRecording], key: SymmetricKey) async throws -> Int {
        guard let tokenData = KeychainHelper.shared.load(key: tokenKey),
              let accessToken = String(data: tokenData, encoding: .utf8) else {
            throw CloudBackupError.accountUnavailable
        }
        var totalSize = 0
        let session = URLSession.shared
        for r in records {
            guard let data = try? Data(contentsOf: r.url) else { continue }
            let hash = SHA256.hash(data: data)
            let hashString = Data(hash).map { String(format: "%02hhx", $0) }.joined()
            let name = "\(hashString).enc"
            let path = "/Recordio/\(name)"
            var checkReq = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/files/get_metadata")!)
            checkReq.httpMethod = "POST"
            checkReq.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            checkReq.addValue("application/json", forHTTPHeaderField: "Content-Type")
            checkReq.httpBody = try JSONSerialization.data(withJSONObject: ["path": path])
            do {
                let (_, resp) = try await session.data(for: checkReq)
                if let http = resp as? HTTPURLResponse, http.statusCode == 200 { continue }
            } catch {}
            let sealed = try AES.GCM.seal(data, using: key)
            guard let combined = sealed.combined else { continue }
            var uploadReq = URLRequest(url: URL(string: "https://content.dropboxapi.com/2/files/upload")!)
            uploadReq.httpMethod = "POST"
            uploadReq.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            uploadReq.addValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            let arg: [String: Any] = ["path": path, "mode": "add", "mute": true]
            let argData = try JSONSerialization.data(withJSONObject: arg)
            let argStr = String(data: argData, encoding: .utf8) ?? "{}"
            uploadReq.addValue(argStr, forHTTPHeaderField: "Dropbox-API-Arg")
            uploadReq.httpBody = Data(combined)
            let (_, uResp) = try await session.data(for: uploadReq)
            guard let http = uResp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw CloudBackupError.backupFailed("Dropbox upload failed")
            }
            totalSize += combined.count
        }
        return totalSize
    }
    
    func restore(key: SymmetricKey) async throws {}
}

final class BoxProvider: CloudProvider {
    let name = "Box"
    private let tokenKey = "com.recordio.box.token"
    private let baseFolderName = "BoxBackups"
    
    func isAvailable() async -> Bool {
        return KeychainHelper.shared.load(key: tokenKey) != nil
    }
    
    func authorize() async throws {
        try await OAuthManager.shared.startAuthorization(for: .box)
    }
    
    func backup(records: [CloudBackupService.LocalRecording], key: SymmetricKey) async throws -> Int {
        guard let tokenData = KeychainHelper.shared.load(key: tokenKey),
              let accessToken = String(data: tokenData, encoding: .utf8) else {
            throw CloudBackupError.accountUnavailable
        }
        var totalSize = 0
        let session = URLSession.shared
        for r in records {
            guard let data = try? Data(contentsOf: r.url) else { continue }
            let hash = SHA256.hash(data: data)
            let hashString = Data(hash).map { String(format: "%02hhx", $0) }.joined()
            let name = "\(hashString).enc"
            var searchComps = URLComponents(string: "https://api.box.com/2.0/search")!
            searchComps.queryItems = [
                URLQueryItem(name: "query", value: name),
                URLQueryItem(name: "type", value: "file"),
                URLQueryItem(name: "fields", value: "name")
            ]
            var searchReq = URLRequest(url: searchComps.url!)
            searchReq.httpMethod = "GET"
            searchReq.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            do {
                let (sData, sResp) = try await session.data(for: searchReq)
                if let http = sResp as? HTTPURLResponse, http.statusCode == 200 {
                    if let obj = try? JSONSerialization.jsonObject(with: sData) as? [String: Any],
                       let entries = obj["entries"] as? [[String: Any]],
                       entries.contains(where: { ($0["name"] as? String) == name }) {
                        continue
                    }
                }
            } catch {}
            let sealed = try AES.GCM.seal(data, using: key)
            guard let combined = sealed.combined else { continue }
            let boundary = "Boundary-\(UUID().uuidString)"
            var uploadReq = URLRequest(url: URL(string: "https://upload.box.com/api/2.0/files/content")!)
            uploadReq.httpMethod = "POST"
            uploadReq.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            uploadReq.addValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            let attributes: [String: Any] = [
                "name": name,
                "parent": ["id": "0"]
            ]
            let attrData = try JSONSerialization.data(withJSONObject: attributes)
            var body = Data()
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"attributes\"\r\n".utf8))
            body.append(Data("Content-Type: application/json\r\n\r\n".utf8))
            body.append(attrData)
            body.append(Data("\r\n--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(name)\"\r\n".utf8))
            body.append(Data("Content-Type: application/octet-stream\r\n\r\n".utf8))
            body.append(Data(combined))
            body.append(Data("\r\n--\(boundary)--\r\n".utf8))
            uploadReq.httpBody = body
            let (_, uResp) = try await session.data(for: uploadReq)
            guard let http = uResp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw CloudBackupError.backupFailed("Box upload failed")
            }
            totalSize += combined.count
        }
        return totalSize
    }
    
    func restore(key: SymmetricKey) async throws {}
}

final class OneDriveProvider: CloudProvider {
    let name = "OneDrive"
    private let tokenKey = "com.recordio.onedrive.token"
    private let baseFolderName = "OneDriveBackups"
    
    func isAvailable() async -> Bool {
        return KeychainHelper.shared.load(key: tokenKey) != nil
    }
    
    func authorize() async throws {
        try await OAuthManager.shared.startAuthorization(for: .oneDrive)
    }
    
    func backup(records: [CloudBackupService.LocalRecording], key: SymmetricKey) async throws -> Int {
        guard let tokenData = KeychainHelper.shared.load(key: tokenKey),
              let accessToken = String(data: tokenData, encoding: .utf8) else {
            throw CloudBackupError.accountUnavailable
        }
        var totalSize = 0
        let session = URLSession.shared
        for r in records {
            guard let data = try? Data(contentsOf: r.url) else { continue }
            let hash = SHA256.hash(data: data)
            let hashString = Data(hash).map { String(format: "%02hhx", $0) }.joined()
            let name = "\(hashString).enc"
            let basePath = "Recordio"
            var metaReq = URLRequest(url: URL(string: "https://graph.microsoft.com/v1.0/me/drive/root:/\(basePath)/\(name)")!)
            metaReq.httpMethod = "GET"
            metaReq.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            do {
                let (_, mResp) = try await session.data(for: metaReq)
                if let http = mResp as? HTTPURLResponse, http.statusCode == 200 { continue }
            } catch {}
            let sealed = try AES.GCM.seal(data, using: key)
            guard let combined = sealed.combined else { continue }
            var putReq = URLRequest(url: URL(string: "https://graph.microsoft.com/v1.0/me/drive/root:/\(basePath)/\(name):/content")!)
            putReq.httpMethod = "PUT"
            putReq.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            putReq.addValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            putReq.httpBody = Data(combined)
            let (_, uResp) = try await session.data(for: putReq)
            guard let http = uResp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw CloudBackupError.backupFailed("OneDrive upload failed")
            }
            totalSize += combined.count
        }
        return totalSize
    }
    
    func restore(key: SymmetricKey) async throws {}
}
final class ICloudProvider: CloudProvider {
    let name = "iCloud"
    private let container: CKContainer
    private let database: CKDatabase
    
    init(container: CKContainer, database: CKDatabase) {
        self.container = container
        self.database = database
    }
    
    func isAvailable() async -> Bool {
        do {
            let status = try await container.accountStatus()
            return status == .available
        } catch {
            return false
        }
    }
    
    func authorize() async throws {}
    
    func backup(records: [CloudBackupService.LocalRecording], key: SymmetricKey) async throws -> Int {
        var totalSize = 0
        for r in records {
            if try await recordExists(for: r) { continue }
            let record = try await createRecord(from: r, key: key)
            try await database.save(record)
            totalSize += r.fileSize
        }
        return totalSize
    }
    
    func restore(key: SymmetricKey) async throws {}
    
    private func createRecord(from recording: CloudBackupService.LocalRecording, key: SymmetricKey) async throws -> CKRecord {
        let record = CKRecord(recordType: "RecordingRecord")
        record["id"] = recording.id.uuidString
        record["title"] = recording.title ?? "Untitled Recording"
        record["createdAt"] = recording.createdAt
        record["fileSize"] = recording.fileSize
        
        guard let audioData = try? Data(contentsOf: recording.url) else {
            throw CloudBackupError.fileReadError
        }
        let hash = SHA256.hash(data: audioData)
        let hashString = Data(hash).map { String(format: "%02hhx", $0) }.joined()
        record["contentHash"] = hashString
        let sealedBox = try AES.GCM.seal(audioData, using: key)
        guard let combined = sealedBox.combined else { throw CloudBackupError.encryptionFailed("Failed to encrypt data") }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(recording.id.uuidString)_encrypted.m4a")
        try Data(combined).write(to: tempURL)
        let asset = CKAsset(fileURL: tempURL)
        record["audioFile"] = asset
        return record
    }
    
    private func recordExists(for recording: CloudBackupService.LocalRecording) async throws -> Bool {
        guard let audioData = try? Data(contentsOf: recording.url) else { return false }
        let hash = SHA256.hash(data: audioData)
        let hashString = Data(hash).map { String(format: "%02hhx", $0) }.joined()
        let predicate = NSPredicate(format: "contentHash == %@", hashString)
        let query = CKQuery(recordType: "RecordingRecord", predicate: predicate)
        
        return await withCheckedContinuation { continuation in
            let operation = CKQueryOperation(query: query)
            operation.resultsLimit = 1
            operation.desiredKeys = ["recordID"]
            var found = false
            
            operation.recordMatchedBlock = { _, result in
                if case .success(_) = result { found = true }
            }
            
            operation.queryCompletionBlock = { _, error in
                if let error = error {
                    print("Error checking record existence: \(error)")
                    continuation.resume(returning: false)
                } else {
                    continuation.resume(returning: found)
                }
            }
            
            database.add(operation)
        }
    }
}
