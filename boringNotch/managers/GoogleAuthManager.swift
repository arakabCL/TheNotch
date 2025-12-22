//
//  GoogleAuthManager.swift
//  boringNotch
//
//  Created for Google Calendar integration
//

import Foundation
import Security
import CommonCrypto
import AppKit

/// OAuth2 authentication manager for Google Calendar API using PKCE flow
@MainActor
class GoogleAuthManager: ObservableObject {
    static let shared = GoogleAuthManager()
    
    // MARK: - Published Properties
    @Published var isSignedIn: Bool = false
    @Published var isAuthenticating: Bool = false
    @Published var userEmail: String?
    @Published var errorMessage: String?
    
    // MARK: - OAuth2 Configuration
    // Credentials are stored in Keychain - configure via Settings
    private let clientIdKey = "com.boringNotch.googleCalendar.clientId"
    private let clientSecretKey = "com.boringNotch.googleCalendar.clientSecret"
    
    private var clientId: String {
        getFromKeychain(key: clientIdKey) ?? ""
    }
    
    private var clientSecret: String {
        getFromKeychain(key: clientSecretKey) ?? ""
    }
    
    private let redirectUri = "http://127.0.0.1:8080/oauth/callback"
    private let scope = "https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/userinfo.email https://www.googleapis.com/auth/userinfo.profile openid"
    private let authorizationEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    private let tokenEndpoint = "https://oauth2.googleapis.com/token"
    
    // MARK: - Token Storage Keys
    private let accessTokenKey = "com.boringNotch.googleCalendar.accessToken"
    private let refreshTokenKey = "com.boringNotch.googleCalendar.refreshToken"
    private let expirationKey = "com.boringNotch.googleCalendar.expiration"
    private let emailKey = "com.boringNotch.googleCalendar.email"
    
    // MARK: - Public Configuration Methods
    
    /// Check if OAuth credentials are configured
    var hasCredentials: Bool {
        !clientId.isEmpty && !clientSecret.isEmpty
    }
    
    /// Configure OAuth credentials (stores in Keychain)
    func setCredentials(clientId: String, clientSecret: String) {
        saveToKeychain(key: clientIdKey, value: clientId)
        saveToKeychain(key: clientSecretKey, value: clientSecret)
    }
    
    /// Clear OAuth credentials
    func clearCredentials() {
        deleteFromKeychain(key: clientIdKey)
        deleteFromKeychain(key: clientSecretKey)
        signOut()
    }
    
    // MARK: - PKCE Properties
    private var codeVerifier: String?
    private var localServer: LocalOAuthServer?
    
    // MARK: - Initialization
    private init() {
        loadStoredCredentials()
    }
    
    // MARK: - Public Methods
    
    /// Initiates the Google OAuth2 sign-in flow
    func signIn() async {
        guard !isAuthenticating else { return }
        
        isAuthenticating = true
        errorMessage = nil
        
        do {
            // Generate PKCE code verifier and challenge
            codeVerifier = generateCodeVerifier()
            guard let verifier = codeVerifier else {
                throw GoogleAuthError.pkceGenerationFailed
            }
            let codeChallenge = generateCodeChallenge(from: verifier)
            
            // Start local server to receive callback
            localServer = LocalOAuthServer()
            
            // Build authorization URL
            let state = UUID().uuidString
            localServer?.expectedState = state
            
            var components = URLComponents(string: authorizationEndpoint)!
            components.queryItems = [
                URLQueryItem(name: "client_id", value: clientId),
                URLQueryItem(name: "redirect_uri", value: redirectUri),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "scope", value: scope),
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "code_challenge", value: codeChallenge),
                URLQueryItem(name: "code_challenge_method", value: "S256"),
                URLQueryItem(name: "access_type", value: "offline"),
                URLQueryItem(name: "prompt", value: "consent")
            ]
            
            guard let authURL = components.url else {
                throw GoogleAuthError.invalidAuthorizationURL
            }
            
            // Open browser for user authentication
            NSWorkspace.shared.open(authURL)
            
            // Wait for callback (this will block until user completes auth or timeout)
            let authCode = try await localServer!.waitForAuthorizationCode()
            
            // Exchange code for tokens
            try await exchangeCodeForTokens(authCode)
            
            isSignedIn = true
            
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Google Auth Error: \(error)")
        }
        
        isAuthenticating = false
        localServer?.stop()
        localServer = nil
    }
    
    /// Signs out and clears stored credentials
    func signOut() {
        deleteFromKeychain(key: accessTokenKey)
        deleteFromKeychain(key: refreshTokenKey)
        deleteFromKeychain(key: expirationKey)
        deleteFromKeychain(key: emailKey)
        
        isSignedIn = false
        userEmail = nil
        errorMessage = nil
    }
    
    /// Returns a valid access token, refreshing if necessary
    func getValidAccessToken() async throws -> String {
        // Check if we have a stored token
        guard let accessToken = getFromKeychain(key: accessTokenKey) else {
            throw GoogleAuthError.notSignedIn
        }
        
        // Check if token is expired
        if let expirationString = getFromKeychain(key: expirationKey),
           let expirationInterval = Double(expirationString) {
            let expirationDate = Date(timeIntervalSince1970: expirationInterval)
            
            // Refresh if expires within 5 minutes
            if expirationDate.timeIntervalSinceNow < 300 {
                try await refreshAccessToken()
                guard let newToken = getFromKeychain(key: accessTokenKey) else {
                    throw GoogleAuthError.tokenRefreshFailed
                }
                return newToken
            }
        }
        
        return accessToken
    }
    
    // MARK: - Private Methods
    
    private func loadStoredCredentials() {
        if let _ = getFromKeychain(key: accessTokenKey) {
            isSignedIn = true
            userEmail = getFromKeychain(key: emailKey)
        }
    }
    
    private func waitForAuthorizationCode() async throws -> String {
        guard let server = localServer else {
            throw GoogleAuthError.serverNotStarted
        }
        
        return try await server.waitForAuthorizationCode()
    }
    
    private func exchangeCodeForTokens(_ code: String) async throws {
        guard let verifier = codeVerifier else {
            throw GoogleAuthError.pkceVerifierMissing
        }
        
        var request = URLRequest(url: URL(string: tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyParams = [
            "client_id": clientId,
            "client_secret": clientSecret,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectUri
        ]
        
        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleAuthError.tokenExchangeFailed
        }
        
        if httpResponse.statusCode != 200 {
            if let responseString = String(data: data, encoding: .utf8) {
                print("❌ Token Exchange Failed Body: \(responseString)")
            }
            throw GoogleAuthError.tokenExchangeFailed
        }
        
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        
        // Store tokens
        saveToKeychain(key: accessTokenKey, value: tokenResponse.accessToken)
        if let refreshToken = tokenResponse.refreshToken {
            saveToKeychain(key: refreshTokenKey, value: refreshToken)
        }
        
        let expiration = Date().timeIntervalSince1970 + Double(tokenResponse.expiresIn)
        saveToKeychain(key: expirationKey, value: String(expiration))
        
        // Fetch user info
        await fetchUserInfo(accessToken: tokenResponse.accessToken)
    }
    
    private func refreshAccessToken() async throws {
        guard let refreshToken = getFromKeychain(key: refreshTokenKey) else {
            throw GoogleAuthError.noRefreshToken
        }
        
        var request = URLRequest(url: URL(string: tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyParams = [
            "client_id": clientId,
            "client_secret": clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        
        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            // Refresh token expired, need to re-authenticate
            signOut()
            throw GoogleAuthError.tokenRefreshFailed
        }
        
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        
        saveToKeychain(key: accessTokenKey, value: tokenResponse.accessToken)
        let expiration = Date().timeIntervalSince1970 + Double(tokenResponse.expiresIn)
        saveToKeychain(key: expirationKey, value: String(expiration))
    }
    
    private func fetchUserInfo(accessToken: String) async {
        let userInfoURL = URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!
        var request = URLRequest(url: userInfoURL)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let responseString = String(data: data, encoding: .utf8) {
                print("👤 User Info Response: \(responseString)")
            }
            let userInfo = try JSONDecoder().decode(UserInfo.self, from: data)
            userEmail = userInfo.email
            if let email = userInfo.email {
                saveToKeychain(key: emailKey, value: email)
            }
        } catch {
            print("Failed to fetch user info: \(error)")
        }
    }
    
    // MARK: - PKCE Helpers
    
    private func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    private func generateCodeChallenge(from verifier: String) -> String {
        guard let data = verifier.data(using: .utf8) else { return "" }
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    // MARK: - Keychain Helpers
    
    private func saveToKeychain(key: String, value: String) {
        let data = value.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "com.boring.notch"
        ]
        
        SecItemDelete(query as CFDictionary)
        
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "com.boring.notch",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        SecItemAdd(attributes as CFDictionary, nil)
    }
    
    private func getFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "com.boring.notch",
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return value
    }
    
    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "com.boring.notch"
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Supporting Types

struct TokenResponse: Codable {
    let accessToken: String
    let expiresIn: Int
    let refreshToken: String?
    let scope: String?
    let tokenType: String
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
        case tokenType = "token_type"
    }
}

struct UserInfo: Codable {
    let id: String?
    let sub: String?
    let email: String?
    let name: String?
    let picture: String?
}

enum GoogleAuthError: LocalizedError {
    case pkceGenerationFailed
    case invalidAuthorizationURL
    case serverNotStarted
    case authorizationFailed
    case tokenExchangeFailed
    case tokenRefreshFailed
    case noRefreshToken
    case notSignedIn
    case pkceVerifierMissing
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .pkceGenerationFailed: return "Failed to generate PKCE codes"
        case .invalidAuthorizationURL: return "Invalid authorization URL"
        case .serverNotStarted: return "OAuth callback server not started"
        case .authorizationFailed: return "Authorization failed"
        case .tokenExchangeFailed: return "Failed to exchange code for tokens"
        case .tokenRefreshFailed: return "Failed to refresh access token"
        case .noRefreshToken: return "No refresh token available"
        case .notSignedIn: return "Not signed in to Google"
        case .pkceVerifierMissing: return "PKCE verifier missing"
        case .timeout: return "Authentication timed out"
        }
    }
}

// MARK: - Local OAuth Server

/// Simple HTTP server to receive OAuth callback on loopback address
class LocalOAuthServer: @unchecked Sendable {
    private var serverSocket: Int32 = -1
    private var isRunning = false
    private let lock = NSRecursiveLock()
    var expectedState: String?
    
    private var authCodeContinuation: CheckedContinuation<String, Error>?
    
    func startAndWaitForCallback() async throws -> (code: String, state: String) {
        // This method is now handled by waitForAuthorizationCode
        return ("", "")
    }
    
    func waitForAuthorizationCode() async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            self.authCodeContinuation = continuation
            lock.unlock()
            
            DispatchQueue.global(qos: .userInitiated).async {
                self.startServer()
            }
            
            // Set timeout
            Task {
                try await Task.sleep(nanoseconds: 120_000_000_000) // 2 minutes
                self.resumeWith(error: GoogleAuthError.timeout)
            }
        }
    }
    
    private func resumeWith(code: String) {
        lock.lock()
        defer { lock.unlock() }
        if let continuation = authCodeContinuation {
            continuation.resume(returning: code)
            authCodeContinuation = nil
            self.stop()
        }
    }
    
    private func resumeWith(error: Error) {
        lock.lock()
        defer { lock.unlock() }
        if let continuation = authCodeContinuation {
            continuation.resume(throwing: error)
            authCodeContinuation = nil
            self.stop()
        }
    }
    
    private func startServer() {
        serverSocket = socket(AF_INET, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            resumeWith(error: GoogleAuthError.serverNotStarted)
            return
        }
        
        var reuseAddr: Int32 = 1
        setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &reuseAddr, socklen_t(MemoryLayout<Int32>.size))
        
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(8080).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverSocket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        guard bindResult >= 0 else {
            close(serverSocket)
            resumeWith(error: GoogleAuthError.serverNotStarted)
            return
        }
        
        guard listen(serverSocket, 5) >= 0 else {
            close(serverSocket)
            resumeWith(error: GoogleAuthError.serverNotStarted)
            return
        }
        
        isRunning = true
        
        while isRunning {
            var clientAddr = sockaddr_in()
            var clientAddrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let clientSocket = withUnsafeMutablePointer(to: &clientAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    accept(serverSocket, $0, &clientAddrLen)
                }
            }
            
            guard clientSocket >= 0 else {
                if isRunning {
                    continue
                } else {
                    break
                }
            }
            
            // Read request
            var buffer = [UInt8](repeating: 0, count: 4096)
            let bytesRead = read(clientSocket, &buffer, buffer.count)
            
            if bytesRead > 0 {
                let requestString = String(bytes: buffer.prefix(bytesRead), encoding: .utf8) ?? ""
                print("DEBUG: Received request:\n\(requestString.prefix(100))...")
                
                // Parse authorization code from request
                if let code = parseAuthorizationCode(from: requestString) {
                    print("DEBUG: Successfully parsed auth code")
                    // Send success response
                    let successHTML = """
                    HTTP/1.1 200 OK\r
                    Content-Type: text/html; charset=UTF-8\r
                    Connection: close\r
                    \r
                    <html><body style="font-family: -apple-system, sans-serif; text-align: center; padding: 50px;">
                    <div style="font-size: 48px; margin-bottom: 20px;">✅</div>
                    <h1>Authentication Successful</h1>
                    <p>You can close this window and return to Boring Notch.</p>
                    <script>window.close();</script>
                    </body></html>
                    """
                    write(clientSocket, successHTML, successHTML.utf8.count)
                    close(clientSocket)
                    
                    resumeWith(code: code)
                    break // Exit the loop on success
                } else if requestString.contains("favicon.ico") {
                    // Ignore favicon requests, just close the connection
                    let emptyResponse = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                    write(clientSocket, emptyResponse, emptyResponse.utf8.count)
                    close(clientSocket)
                } else {
                    // Send error response for actual non-callback requests
                    let errorHTML = """
                    HTTP/1.1 400 Bad Request\r
                    Content-Type: text/html; charset=UTF-8\r
                    Connection: close\r
                    \r
                    <html><body style="font-family: -apple-system, sans-serif; text-align: center; padding: 50px;">
                    <div style="font-size: 48px; margin-bottom: 20px;">ℹ️</div>
                    <p>Waiting for Google Calendar authorization...</p>
                    </body></html>
                    """
                    write(clientSocket, errorHTML, errorHTML.utf8.count)
                    close(clientSocket)
                    // Don't break or resumeWith(error) here, keep waiting for the actual callback
                }
            } else {
                close(clientSocket)
            }
        }
        
        self.stop()
    }
    
    private func parseAuthorizationCode(from request: String) -> String? {
        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first, firstLine.hasPrefix("GET") else {
            print("DEBUG: Not a GET request")
            return nil
        }
        
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            print("DEBUG: Invalid request line format")
            return nil
        }
        
        let path = parts[1]
        print("DEBUG: Request path: \(path)")
        
        // Use a dummy base so we can parse query items
        guard let components = URLComponents(string: "http://localhost\(path)") else {
            print("DEBUG: Failed to parse path into URLComponents")
            return nil
        }
        
        // Log all query items for debugging
        if let queryItems = components.queryItems {
            for item in queryItems {
                print("DEBUG: QueryParam: \(item.name) = \(item.name == "code" ? "[REDACTED]" : (item.value ?? "nil"))")
            }
        }
        
        // Check for error
        if let error = components.queryItems?.first(where: { $0.name == "error" })?.value {
            print("❌ OAuth error from Google: \(error)")
            return nil
        }
        
        // Validate state
        if let expectedState = expectedState {
            let receivedState = components.queryItems?.first(where: { $0.name == "state" })?.value
            if receivedState != expectedState {
                print("❌ OAuth state mismatch! Expected: \(expectedState), Received: \(receivedState ?? "nil")")
                return nil
            }
        }
        
        let code = components.queryItems?.first(where: { $0.name == "code" })?.value
        if code == nil {
            print("DEBUG: No 'code' found in query items")
        }
        return code
    }
    
    func stop() {
        lock.lock()
        defer { lock.unlock() }
        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }
        isRunning = false
    }
}
