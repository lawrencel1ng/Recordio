import Foundation
import AuthenticationServices

class OAuthManager: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = OAuthManager()
    
    private var currentSession: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<Void, Error>?
    private let keychain = KeychainHelper.shared
    
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(iOS)
        return UIApplication.shared.windows.first ?? ASPresentationAnchor()
        #else
        return ASPresentationAnchor()
        #endif
    }
    
    func startAuthorization(for provider: BackupProviderType) async throws {
        guard let config = oauthConfig(for: provider) else {
            throw CloudBackupError.accountUnavailable
        }
        let state = UUID().uuidString
        var components = URLComponents(string: config.authURL)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "scope", value: config.scope),
            URLQueryItem(name: "state", value: state),
        ]
        guard let url = components.url else {
            throw CloudBackupError.accountUnavailable
        }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: URL(string: config.redirectURI)?.scheme) { callbackURL, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL = callbackURL else {
                    continuation.resume(throwing: CloudBackupError.accountUnavailable)
                    return
                }
                self.handleCallback(url: callbackURL, provider: provider, config: config)
            }
            session.prefersEphemeralWebBrowserSession = true
            session.presentationContextProvider = self
            self.currentSession = session
            _ = session.start()
        }
    }
    
    private func handleCallback(url: URL, provider: BackupProviderType, config: OAuthConfig) {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = comps.queryItems?.first(where: { $0.name == "code" })?.value else {
            continuation?.resume(throwing: CloudBackupError.accountUnavailable)
            continuation = nil
            return
        }
        Task {
            do {
                let token = try await exchangeCodeForToken(code: code, config: config)
                keychain.save(key: config.tokenKey, data: Data(token.accessToken.utf8))
                continuation?.resume()
            } catch {
                continuation?.resume(throwing: error)
            }
            continuation = nil
        }
    }
    
    private func exchangeCodeForToken(code: String, config: OAuthConfig) async throws -> OAuthToken {
        var req = URLRequest(url: URL(string: config.tokenURL)!)
        req.httpMethod = "POST"
        let body = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": config.redirectURI,
            "client_id": config.clientId,
            "code_verifier": ""
        ]
        let bodyStr = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
        req.httpBody = bodyStr.data(using: .utf8)
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw CloudBackupError.accountUnavailable
        }
        let token = try JSONDecoder().decode(OAuthToken.self, from: data)
        return token
    }
    
    struct OAuthConfig {
        let authURL: String
        let tokenURL: String
        let clientId: String
        let redirectURI: String
        let scope: String
        let tokenKey: String
    }
    
    struct OAuthToken: Codable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int?
        
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }
    
    private func oauthConfig(for provider: BackupProviderType) -> OAuthConfig? {
        let defaults = UserDefaults.standard
        switch provider {
        case .googleDrive:
            guard let clientId = defaults.string(forKey: "oauth.gdrive.client_id") else { return nil }
            return OAuthConfig(
                authURL: "https://accounts.google.com/o/oauth2/v2/auth",
                tokenURL: "https://oauth2.googleapis.com/token",
                clientId: clientId,
                redirectURI: "recordio://oauth/callback",
                scope: "https://www.googleapis.com/auth/drive.file",
                tokenKey: "com.recordio.gdrive.token"
            )
        case .dropbox:
            guard let clientId = defaults.string(forKey: "oauth.dropbox.client_id") else { return nil }
            return OAuthConfig(
                authURL: "https://www.dropbox.com/oauth2/authorize",
                tokenURL: "https://api.dropbox.com/oauth2/token",
                clientId: clientId,
                redirectURI: "recordio://oauth/callback",
                scope: "files.content.write",
                tokenKey: "com.recordio.dropbox.token"
            )
        case .box:
            guard let clientId = defaults.string(forKey: "oauth.box.client_id") else { return nil }
            return OAuthConfig(
                authURL: "https://account.box.com/api/oauth2/authorize",
                tokenURL: "https://api.box.com/oauth2/token",
                clientId: clientId,
                redirectURI: "recordio://oauth/callback",
                scope: "item_upload",
                tokenKey: "com.recordio.box.token"
            )
        case .oneDrive:
            guard let clientId = defaults.string(forKey: "oauth.onedrive.client_id") else { return nil }
            return OAuthConfig(
                authURL: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
                tokenURL: "https://login.microsoftonline.com/common/oauth2/v2.0/token",
                clientId: clientId,
                redirectURI: "recordio://oauth/callback",
                scope: "Files.ReadWrite",
                tokenKey: "com.recordio.onedrive.token"
            )
        case .iCloud:
            return nil
        }
    }
}
