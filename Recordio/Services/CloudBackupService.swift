import Foundation
import CloudKit
import CryptoKit
import Combine

class CloudBackupService: ObservableObject {
    static let shared = CloudBackupService()
    
    @Published var isBackupEnabled = false
    @Published var isBackupInProgress = false
    @Published var lastBackupDate: Date?
    @Published var backupSize: String?
    @Published var error: CloudBackupError?
    @Published var isAvailable: Bool = false
    
    private lazy var container = CKContainer(identifier: "iCloud.com.recordio")
    private lazy var database = container.privateCloudDatabase
    
    private let keychainKey = "com.recordio.encryption.key"
    
    private init() {
        isAvailable = FileManager.default.ubiquityIdentityToken != nil
        loadBackupSettings()
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
        
        if encryptionKey == nil {
            generateEncryptionKey()
        }
        
        do {
            let status = try await container.accountStatus()
            
            switch status {
            case .available, .noAccount:
                isBackupEnabled = true
                saveBackupSettings()
                
                await MainActor.run {
                    self.isBackupInProgress = false
                }
                
                await performBackup()
                
            case .restricted:
                await MainActor.run {
                    self.error = .accountRestricted
                    self.isBackupInProgress = false
                }
                
            case .couldNotDetermine, .temporarilyUnavailable:
                await MainActor.run {
                    self.error = .accountUnavailable
                    self.isBackupInProgress = false
                }
            @unknown default:
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
            let operation = CKQueryOperation(query: query)
            var recordIDs: [CKRecord.ID] = []
            
            operation.recordMatchedBlock = { recordID, _ in
                recordIDs.append(recordID)
            }
            
            operation.queryCompletionBlock = { _, error in
                if let error = error {
                    Task { @MainActor in
                        self.error = .backupFailed(error.localizedDescription)
                        self.isBackupInProgress = false
                    }
                    return
                }
                
                Task {
                    let deleteOperation = CKModifyRecordsOperation(recordIDsToDelete: recordIDs)
                    deleteOperation.modifyRecordsCompletionBlock = { _, _, error in
                        Task { @MainActor in
                            if let error = error {
                                self.error = .backupFailed(error.localizedDescription)
                            } else {
                                self.isBackupEnabled = false
                                self.saveBackupSettings()
                            }
                            self.isBackupInProgress = false
                        }
                    }
                    
                    await self.database.add(deleteOperation)
                }
            }
            
            await database.add(operation)
        } catch {
            await MainActor.run {
                self.error = .backupFailed(error.localizedDescription)
                self.isBackupInProgress = false
            }
        }
    }
    
    func performBackup() async {
        guard isAvailable else { return }
        guard isBackupEnabled else { return }
        
        isBackupInProgress = true
        error = nil
        
        do {
            let recordings = try await fetchLocalRecordings()
            var totalSize: Int = 0
            
            for recording in recordings {
                if let record = try await createCloudRecord(from: recording) {
                    try await database.save(record)
                    totalSize += recording.fileSize
                }
            }
            
            await MainActor.run {
                self.lastBackupDate = Date()
                self.backupSize = formatBytes(totalSize)
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
    
    func restoreFromBackup() async throws {
        guard let key = encryptionKey else {
            throw CloudBackupError.encryptionKeyMissing
        }
        
        isBackupInProgress = true
        
        let query = CKQuery(recordType: "RecordingRecord", predicate: NSPredicate(value: true))
        
        let operation = CKQueryOperation(query: query)
        var records: [CKRecord] = []
        
        operation.recordMatchedBlock = { recordID, result in
            switch result {
            case .success(let record):
                records.append(record)
            case .failure(let error):
                print("Error fetching record: \(error)")
            }
        }
        
        operation.queryCompletionBlock = { _, error in
            if let error = error {
                Task { @MainActor in
                    self.error = .restoreFailed(error.localizedDescription)
                    self.isBackupInProgress = false
                }
            } else {
                Task {
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
            }
        }
        
        await database.add(operation)
    }
    
    private func fetchLocalRecordings() async throws -> [(id: UUID, url: URL, title: String?, createdAt: Date, fileSize: Int)] {
        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recordingsPath = documentsPath.appendingPathComponent("Recordings", isDirectory: true)
        
        guard let contents = try? fileManager.contentsOfDirectory(at: recordingsPath, includingPropertiesForKeys: [.fileSizeKey], options: []) else {
            return []
        }
        
        var recordings: [(id: UUID, url: URL, title: String?, createdAt: Date, fileSize: Int)] = []
        
        for url in contents {
            guard url.pathExtension == "wav" || url.pathExtension == "m4a" else { continue }
            
            let attributes = try? fileManager.attributesOfItem(atPath: url.path)
            let fileSize = attributes?[.size] as? Int ?? 0
            let createdAt = attributes?[.creationDate] as? Date ?? Date()
            let filename = url.deletingPathExtension().lastPathComponent
            
            recordings.append((
                id: UUID(),
                url: url,
                title: filename,
                createdAt: createdAt,
                fileSize: fileSize
            ))
        }
        
        return recordings
    }
    
    private func createCloudRecord(from recording: (id: UUID, url: URL, title: String?, createdAt: Date, fileSize: Int)) async throws -> CKRecord? {
        guard let key = encryptionKey else {
            throw CloudBackupError.encryptionKeyMissing
        }
        
        let record = CKRecord(recordType: "RecordingRecord")
        record["id"] = recording.id.uuidString
        record["title"] = recording.title ?? "Untitled Recording"
        record["createdAt"] = recording.createdAt
        record["fileSize"] = recording.fileSize
        
        do {
            guard let audioData = try? Data(contentsOf: recording.url) else {
                throw CloudBackupError.fileReadError
            }
            
            let encryptedData = try encryptData(audioData, using: key)
            
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(recording.id.uuidString)_encrypted.m4a")
            try encryptedData.write(to: tempURL)
            
            let asset = CKAsset(fileURL: tempURL)
            record["audioFile"] = asset
            
            return record
        } catch {
            throw CloudBackupError.encryptionFailed(error.localizedDescription)
        }
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
        
        let filename = record["title"] as? String ?? "Restored Recording"
        let destinationURL = recordingsPath.appendingPathComponent("\(filename)_restored.m4a")
        
        try decryptedData.write(to: destinationURL)
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