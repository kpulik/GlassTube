//
//  AuthManager.swift
//  GlassTube
//
//  Created by Kevin Pulikkottil on 4/11/26.
//

import Foundation
import SwiftUI
import Combine
import Security

/// Manages YouTube/Google OAuth 2.0 authentication using the device code flow.
/// Google rejects the previously bundled shared client, so users must provide
/// their own TVs and Limited Input OAuth credentials in Settings.
@MainActor
class AuthManager: ObservableObject {

    // MARK: - Published State

    @Published var isSignedIn = false
    @Published var userName: String = ""
    @Published var userEmail: String = ""
    @Published var userAvatar: String = ""
    @Published var accessToken: String?

    // Device code flow state
    @Published var deviceCode: String?
    @Published var userCode: String?
    @Published var verificationURL: String?
    @Published var isPolling = false
    @Published var authErrorMessage: String?

    // MARK: - OAuth Configuration

    private let deviceAuthURL = "https://oauth2.googleapis.com/device/code"
    private let tokenURL = "https://oauth2.googleapis.com/token"
    private let userInfoURL = "https://www.googleapis.com/oauth2/v3/userinfo"
    private let oauthSetupURL = "https://developers.google.com/identity/protocols/oauth2/limited-input-device#creatingcred"
    // Google's TV / Limited-Input device flow only allows:
    //   openid, email, profile, drive.appdata, drive.file,
    //   https://www.googleapis.com/auth/youtube,
    //   https://www.googleapis.com/auth/youtube.readonly
    // youtube.force-ssl is NOT on that allowlist — including it makes Google
    // reject the device-code request with invalid_scope. Data API writes that
    // require force-ssl (commentThreads.insert, videos.rate,
    // subscriptions.insert/delete) are therefore not usable from this flow;
    // those paths must go through Innertube (see YouTubeService).
    private let scopes = "openid email profile https://www.googleapis.com/auth/youtube.readonly https://www.googleapis.com/auth/youtube"
    private let oauthClientIDConfigKey = "googleOAuthTVClientID"
    private let oauthClientSecretConfigKey = "googleOAuthTVClientSecret"
    private let oauthScopeVersionKey = "glassTubeOAuthScopeVersion"
    private let oauthScopeVersion = 5

    // Token storage keys
    private let accessTokenKey = "com.glasstube.accessToken"
    private let refreshTokenKey = "com.glasstube.refreshToken"
    private let tokenExpiryKey = "com.glasstube.tokenExpiry"

    private var pollTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        migrateStoredTokenScopesIfNeeded()
        loadStoredTokens()
    }

    // MARK: - OAuth Configuration

    func oauthConfiguration() -> (clientID: String, clientSecret: String) {
        (
            UserDefaults.standard.string(forKey: oauthClientIDConfigKey) ?? "",
            UserDefaults.standard.string(forKey: oauthClientSecretConfigKey) ?? ""
        )
    }

    func saveOAuthConfiguration(clientID: String, clientSecret: String) {
        let trimmedID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedID.isEmpty {
            UserDefaults.standard.removeObject(forKey: oauthClientIDConfigKey)
        } else {
            UserDefaults.standard.set(trimmedID, forKey: oauthClientIDConfigKey)
        }

        if trimmedSecret.isEmpty {
            UserDefaults.standard.removeObject(forKey: oauthClientSecretConfigKey)
        } else {
            UserDefaults.standard.set(trimmedSecret, forKey: oauthClientSecretConfigKey)
        }
    }

    func clearOAuthConfiguration() {
        UserDefaults.standard.removeObject(forKey: oauthClientIDConfigKey)
        UserDefaults.standard.removeObject(forKey: oauthClientSecretConfigKey)
    }

    // MARK: - Device Code Flow

    /// Step 1: Request a device code from Google
    func startDeviceCodeFlow() async {
        authErrorMessage = nil

        guard let oauthCredentials = configuredOAuthCredentials else {
            verificationURL = oauthSetupURL
            authErrorMessage = "Add a valid Google OAuth client ID and client secret in Settings > Authentication before signing in."
            return
        }

        do {
            guard let url = URL(string: deviceAuthURL) else { return }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

            let body = formEncodedBody([
                "client_id": oauthCredentials.clientID,
                "scope": scopes
            ])
            request.httpBody = body

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                authErrorMessage = "OAuth failed: invalid server response."
                return
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    handleOAuthError(
                        code: json["error"] as? String,
                        description: json["error_description"] as? String
                    )
                } else {
                    authErrorMessage = "OAuth failed with HTTP \(httpResponse.statusCode)."
                }
                return
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                authErrorMessage = "OAuth failed: invalid response payload."
                return
            }

            deviceCode = json["device_code"] as? String
            userCode = json["user_code"] as? String
            verificationURL = json["verification_url"] as? String
            let interval = json["interval"] as? Int ?? 5

            // Start polling for the user to authorize
            startPolling(
                interval: interval,
                clientID: oauthCredentials.clientID,
                clientSecret: oauthCredentials.clientSecret
            )
        } catch {
            authErrorMessage = "Sign in failed: \(error.localizedDescription)"
        }
    }

    /// Step 2: Poll for authorization
    private func startPolling(interval: Int, clientID: String, clientSecret: String) {
        guard let deviceCode else { return }
        isPolling = true
        authErrorMessage = nil

        pollTask?.cancel()
        pollTask = Task {
            var pollInterval = max(2, interval)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(pollInterval))
                if Task.isCancelled { break }

                do {
                    guard let url = URL(string: tokenURL) else { continue }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

                    let body = formEncodedBody([
                        "client_id": clientID,
                        "client_secret": clientSecret,
                        "device_code": deviceCode,
                        "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
                    ])
                    request.httpBody = body

                    let (data, _) = try await URLSession.shared.data(for: request)
                    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

                    if let accessToken = json["access_token"] as? String {
                        let refreshToken = json["refresh_token"] as? String
                        let expiresIn = json["expires_in"] as? Int ?? 3600

                        self.accessToken = accessToken
                        storeTokens(
                            access: accessToken,
                            refresh: refreshToken,
                            expiresIn: expiresIn
                        )

                        await fetchUserInfo()
                        isSignedIn = true
                        isPolling = false
                        self.deviceCode = nil
                        self.userCode = nil
                        self.verificationURL = nil
                        return
                    }

                    // Check for errors
                    if let error = json["error"] as? String {
                        if error == "access_denied" {
                            isPolling = false
                            self.deviceCode = nil
                            self.userCode = nil
                            self.verificationURL = nil
                            handleOAuthError(
                                code: error,
                                description: json["error_description"] as? String
                            )
                            return
                        }
                        if error == "expired_token" {
                            isPolling = false
                            self.deviceCode = nil
                            self.userCode = nil
                            self.verificationURL = nil
                            authErrorMessage = "Your sign-in code expired. Start sign-in again and complete Google authorization within a few minutes."
                            return
                        }
                        if error == "slow_down" {
                            pollInterval += 5
                            continue
                        }
                        if error == "authorization_pending" {
                            continue
                        }

                        isPolling = false
                        self.deviceCode = nil
                        self.userCode = nil
                        handleOAuthError(
                            code: error,
                            description: json["error_description"] as? String
                        )
                        return
                    }
                } catch {
                    // Network error, will retry
                }
            }
        }
    }

    // MARK: - User Info

    func fetchUserInfo() async {
        guard let token = accessToken,
              let url = URL(string: userInfoURL) else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                userName = json["name"] as? String ?? "YouTube User"
                userEmail = json["email"] as? String ?? ""
                userAvatar = json["picture"] as? String ?? ""
            }
        } catch {}
    }

    // MARK: - Token Refresh

    func refreshAccessToken() async -> Bool {
        guard let oauthCredentials = configuredOAuthCredentials else {
            authErrorMessage = "OAuth credentials are missing. Re-enter them in Settings > Authentication."
            return false
        }

        guard let refreshToken = loadFromKeychain(key: refreshTokenKey),
              let url = URL(string: tokenURL) else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        request.httpBody = formEncodedBody([
            "client_id": oauthCredentials.clientID,
            "client_secret": oauthCredentials.clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ])

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let newAccessToken = json["access_token"] as? String else { return false }

            let expiresIn = json["expires_in"] as? Int ?? 3600
            self.accessToken = newAccessToken
            storeTokens(access: newAccessToken, refresh: nil, expiresIn: expiresIn)
            return true
        } catch {
            return false
        }
    }

    /// Get a valid access token, refreshing if needed
    func getValidToken() async -> String? {
        if let expiry = UserDefaults.standard.object(forKey: tokenExpiryKey) as? Date,
           expiry < Date() {
            let refreshed = await refreshAccessToken()
            if !refreshed {
                signOut()
                return nil
            }
        }
        return accessToken
    }

    // MARK: - Sign Out

    func signOut() {
        accessToken = nil
        isSignedIn = false
        userName = ""
        userEmail = ""
        userAvatar = ""
        deviceCode = nil
        userCode = nil
        verificationURL = nil
        isPolling = false
        authErrorMessage = nil
        pollTask?.cancel()

        deleteFromKeychain(key: accessTokenKey)
        deleteFromKeychain(key: refreshTokenKey)
        UserDefaults.standard.removeObject(forKey: tokenExpiryKey)
    }

    func cancelSignIn() {
        pollTask?.cancel()
        isPolling = false
        deviceCode = nil
        userCode = nil
        verificationURL = nil
    }

    // MARK: - OAuth Helpers

    private var configuredClientID: String {
        UserDefaults.standard.string(forKey: oauthClientIDConfigKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var configuredClientSecret: String {
        UserDefaults.standard.string(forKey: oauthClientSecretConfigKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var hasOAuthConfiguration: Bool {
        !configuredClientID.isEmpty && !configuredClientSecret.isEmpty
    }

    private var configuredOAuthCredentials: (clientID: String, clientSecret: String)? {
        guard !configuredClientID.isEmpty, !configuredClientSecret.isEmpty else {
            return nil
        }
        return (configuredClientID, configuredClientSecret)
    }

    private func formEncodedBody(_ values: [String: String]) -> Data {
        let encoded = values
            .map { key, value in
                "\(urlEncode(key))=\(urlEncode(value))"
            }
            .joined(separator: "&")
        return encoded.data(using: .utf8) ?? Data()
    }

    private func urlEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=?/\\")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func handleOAuthError(code: String?, description: String?) {
        switch code {
        case "restricted_client", "invalid_client", "unauthorized_client":
            authErrorMessage = "Google rejected this OAuth client. Use a 'TVs and Limited Input devices' OAuth client and ensure YouTube Data API is enabled for the same project."
            verificationURL = oauthSetupURL
        case "invalid_scope":
            authErrorMessage = "Google rejected one or more requested OAuth scopes for the device flow. The TV/Limited-Input flow only allows youtube and youtube.readonly — scopes like youtube.force-ssl are not supported here. If this persists, confirm your OAuth client type is 'TVs and Limited Input devices' and that YouTube Data API v3 is enabled for the same Google Cloud project."
            verificationURL = oauthSetupURL
        case "access_denied":
            authErrorMessage = "Google blocked this sign-in because the OAuth app is in Testing mode and this Google account is not approved as a test user. In Google Cloud Console, open OAuth consent screen > Audience, add this email in Test users, wait 1-5 minutes, then try again."
            verificationURL = oauthSetupURL
        case let value where value != nil:
            if let description, !description.isEmpty {
                authErrorMessage = "OAuth error (\(value!)): \(description)"
            } else {
                authErrorMessage = "OAuth error: \(value!)"
            }
        default:
            if let description, !description.isEmpty {
                authErrorMessage = description
            } else {
                authErrorMessage = "OAuth failed. Please verify your OAuth client configuration in Settings."
            }
        }
    }

    // MARK: - Keychain Storage

    private func storeTokens(access: String, refresh: String?, expiresIn: Int) {
        saveToKeychain(key: accessTokenKey, value: access)
        if let refresh {
            saveToKeychain(key: refreshTokenKey, value: refresh)
        }
        let expiry = Date().addingTimeInterval(TimeInterval(expiresIn))
        UserDefaults.standard.set(expiry, forKey: tokenExpiryKey)
        UserDefaults.standard.set(oauthScopeVersion, forKey: oauthScopeVersionKey)
    }

    private func migrateStoredTokenScopesIfNeeded() {
        let storedVersion = UserDefaults.standard.integer(forKey: oauthScopeVersionKey)
        guard storedVersion < oauthScopeVersion else { return }

        let hadStoredToken = loadFromKeychain(key: accessTokenKey) != nil
            || loadFromKeychain(key: refreshTokenKey) != nil

        deleteFromKeychain(key: accessTokenKey)
        deleteFromKeychain(key: refreshTokenKey)
        UserDefaults.standard.removeObject(forKey: tokenExpiryKey)
        UserDefaults.standard.set(oauthScopeVersion, forKey: oauthScopeVersionKey)

        if hadStoredToken {
            accessToken = nil
            isSignedIn = false
            authErrorMessage = "GlassTube updated its OAuth scopes. Your previous session was cleared — please sign in again so Google can issue a fresh token."
        }
    }

    private func loadStoredTokens() {
        if let token = loadFromKeychain(key: accessTokenKey) {
            accessToken = token
            isSignedIn = true

            // Fetch user info in background
            Task {
                // Check if token needs refresh
                if let expiry = UserDefaults.standard.object(forKey: tokenExpiryKey) as? Date,
                   expiry < Date() {
                    let refreshed = await refreshAccessToken()
                    if !refreshed {
                        signOut()
                        return
                    }
                }
                await fetchUserInfo()
            }
        }
    }

    private func saveToKeychain(key: String, value: String) {
        let data = value.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func loadFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
