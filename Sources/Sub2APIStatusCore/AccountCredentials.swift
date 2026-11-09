import Foundation
import LocalAuthentication
import Security

public struct SavedLoginCredentials: Codable, Equatable, Sendable {
    public let baseURL: String
    public let email: String
    public let password: String

    public init(baseURL: String, email: String, password: String) {
        self.baseURL = AppConfig.normalizedBaseURL(baseURL)
        self.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        self.password = password
    }

    public func matches(_ account: StoredAccount, baseURL: String) -> Bool {
        self.baseURL == AppConfig.normalizedBaseURL(baseURL)
            && self.baseURL == account.baseURL
            && email.caseInsensitiveCompare(account.email) == .orderedSame
            && !email.isEmpty && !password.isEmpty
    }
}

public protocol AccountCredentialStore: Sendable {
    func load(for accountID: String) throws -> SavedLoginCredentials?
    func save(_ credentials: SavedLoginCredentials, for accountID: String) throws
    func delete(for accountID: String) throws
}

public struct KeychainCredentialStore: AccountCredentialStore {
    private let service: String

    public init(service: String = "Sub2APIStatusBar.AccountLogin") {
        self.service = service
    }

    public func load(for accountID: String) throws -> SavedLoginCredentials? {
        var query = itemQuery(for: accountID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        // Background renewal must not repeatedly open Keychain permission dialogs.
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        guard let data = result as? Data else { throw KeychainError(status: errSecDecode) }
        return try JSONDecoder().decode(SavedLoginCredentials.self, from: data)
    }

    public func save(_ credentials: SavedLoginCredentials, for accountID: String) throws {
        let query = itemQuery(for: accountID)
        let data = try JSONEncoder().encode(credentials)
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    public func delete(for accountID: String) throws {
        let status = SecItemDelete(itemQuery(for: accountID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    private func itemQuery(for accountID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID,
        ]
    }
}

private struct KeychainError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        "Could not access the saved login in macOS Keychain (\(status)). Sign in again or check Keychain access."
    }
}
