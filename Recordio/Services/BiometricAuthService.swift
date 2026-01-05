import Foundation
import LocalAuthentication
import Combine

enum BiometricType {
    case none
    case touchID
    case faceID
}

class BiometricAuthService: ObservableObject {
    static let shared = BiometricAuthService()
    
    @Published var isBiometricEnabled = false
    @Published var biometricType: BiometricType = .none
    
    private let keychainKey = "com.recordio.biometric.enabled"
    
    private init() {
        loadBiometricSetting()
        checkBiometricAvailability()
    }
    
    func checkBiometricAvailability() {
        let context = LAContext()
        var error: NSError?
        
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            switch context.biometryType {
            case .none:
                biometricType = .none
            case .touchID:
                biometricType = .touchID
            case .faceID:
                biometricType = .faceID
            @unknown default:
                biometricType = .none
            }
        } else {
            biometricType = .none
        }
    }
    
    var biometricName: String {
        switch biometricType {
        case .touchID:
            return "Touch ID"
        case .faceID:
            return "Face ID"
        case .none:
            return "Biometric"
        }
    }
    
    func authenticate(reason: String, completion: @escaping (Bool, Error?) -> Void) {
        let context = LAContext()
        var error: NSError?
        
        if !context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            if let error = error {
                completion(false, error)
                return
            }
        }
        
        context.localizedCancelTitle = "Cancel"
        context.localizedFallbackTitle = "Use Passcode"
        
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
            DispatchQueue.main.async {
                completion(success, error)
            }
        }
    }
    
    func toggleBiometricLock() async throws {
        if isBiometricEnabled {
            try await disableBiometricLock()
        } else {
            try await enableBiometricLock()
        }
    }
    
    private func enableBiometricLock() async throws {
        try await withCheckedThrowingContinuation { continuation in
            authenticate(reason: "Enable biometric lock to protect your recordings") { success, error in
                if success {
                    self.isBiometricEnabled = true
                    self.saveBiometricSetting(true)
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? BiometricError.authenticationFailed)
                }
            }
        }
    }
    
    private func disableBiometricLock() async throws {
        try await withCheckedThrowingContinuation { continuation in
            authenticate(reason: "Disable biometric lock") { success, error in
                if success {
                    self.isBiometricEnabled = false
                    self.saveBiometricSetting(false)
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? BiometricError.authenticationFailed)
                }
            }
        }
    }
    
    func authenticateAccess() async throws {
        guard isBiometricEnabled else {
            return
        }
        
        try await withCheckedThrowingContinuation { continuation in
            let reason: String
            switch biometricType {
            case .faceID:
                reason = "Unlock Recordio to access your recordings"
            case .touchID:
                reason = "Unlock Recordio to access your recordings"
            case .none:
                reason = "Authenticate to access your recordings"
            }
            
            self.authenticate(reason: reason) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? BiometricError.authenticationFailed)
                }
            }
        }
    }
    
    private func loadBiometricSetting() {
        if let data = KeychainHelper.shared.load(key: keychainKey),
           let isEnabled = try? JSONDecoder().decode(Bool.self, from: data) {
            isBiometricEnabled = isEnabled
        }
    }
    
    private func saveBiometricSetting(_ isEnabled: Bool) {
        if let data = try? JSONEncoder().encode(isEnabled) {
            KeychainHelper.shared.save(key: keychainKey, data: data)
        }
    }
}

enum BiometricError: Error, LocalizedError {
    case authenticationFailed
    case biometricNotAvailable
    case biometricNotEnrolled
    case userCancelled
    case systemCancel
    case passcodeNotSet
    
    var errorDescription: String? {
        switch self {
        case .authenticationFailed:
            return "Authentication failed"
        case .biometricNotAvailable:
            return "Biometric authentication is not available on this device"
        case .biometricNotEnrolled:
            return "No biometric identity enrolled"
        case .userCancelled:
            return "Authentication was cancelled"
        case .systemCancel:
            return "System cancelled authentication"
        case .passcodeNotSet:
            return "A passcode must be set to use biometric authentication"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .biometricNotEnrolled:
            return "Please enroll in Face ID or Touch ID in Settings"
        case .passcodeNotSet:
            return "Please set a passcode in Settings"
        default:
            return nil
        }
    }
}

class KeychainHelper {
    static let shared = KeychainHelper()
    
    private init() {}
    
    func save(key: String, data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)
        
        let addQuery: [String: Any] = query
        SecItemAdd(addQuery as CFDictionary, nil)
    }
    
    func load(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess, let data = result as? Data {
            return data
        }
        
        return nil
    }
    
    func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}
