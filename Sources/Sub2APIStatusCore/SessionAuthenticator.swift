import Foundation

public protocol SessionAuthenticationClient: Sendable {
    func login(email: String, password: String) async throws -> AuthResponse
    func refreshToken(_ refreshToken: String) async throws -> AuthResponse
}

extension Sub2APIClient: SessionAuthenticationClient {}

public enum SessionRecoveryError: LocalizedError, Equatable {
    case savedLoginUnavailable
    case savedLoginDoesNotMatch
    case loginRejected
    case loginPaused
    case loginCooldown

    public var errorDescription: String? {
        switch self {
        case .savedLoginUnavailable:
            "No saved password is available. Sign in with Remember password enabled."
        case .savedLoginDoesNotMatch:
            "The saved login does not match this server and account. Sign in again to update it."
        case .loginRejected:
            "Automatic login was rejected. Sign in again to update your password or complete server verification."
        case .loginPaused:
            "Automatic login is paused after a rejected login. Sign in again to resume."
        case .loginCooldown:
            "Automatic login will retry after a short delay."
        }
    }
}

/// Password-enabled accounts always renew through login, even without a refresh token.
public actor SessionAuthenticator {
    private let credentialStore: any AccountCredentialStore
    private var pausedAccounts = Set<String>()
    private var retryAfter: [String: Date] = [:]
    private var generations: [String: Int] = [:]

    public init(credentialStore: any AccountCredentialStore = KeychainCredentialStore()) {
        self.credentialStore = credentialStore
    }

    public func reset(accountID: String) {
        pausedAccounts.remove(accountID)
        retryAfter.removeValue(forKey: accountID)
        generations[accountID, default: 0] += 1
    }

    public func renewSession(
        config: AppConfig,
        client: any SessionAuthenticationClient,
        now: Date = Date()
    ) async throws -> AuthResponse? {
        guard let account = config.selectedAccount, account.automaticLoginEnabled else {
            guard !config.refreshToken.isEmpty else { return nil }
            return try await client.refreshToken(config.refreshToken)
        }

        guard !pausedAccounts.contains(account.id) else { throw SessionRecoveryError.loginPaused }
        if let retry = retryAfter[account.id], retry > now {
            throw SessionRecoveryError.loginCooldown
        }
        // Avoid repeated password submissions during network outages or server rate limiting.
        retryAfter[account.id] = now.addingTimeInterval(60)
        guard let credentials = try credentialStore.load(for: account.id) else {
            throw SessionRecoveryError.savedLoginUnavailable
        }
        guard credentials.matches(account, baseURL: config.baseURL) else {
            throw SessionRecoveryError.savedLoginDoesNotMatch
        }
        let generation = generations[account.id, default: 0]

        do {
            let response = try await client.login(email: credentials.email, password: credentials.password)
            guard generations[account.id, default: 0] == generation else { return nil }
            retryAfter.removeValue(forKey: account.id)
            return response
        } catch let error as Sub2APIError {
            guard generations[account.id, default: 0] == generation else { return nil }
            switch error {
            case let .badStatus(status, _) where (400..<500).contains(status) && status != 408 && status != 429:
                pausedAccounts.insert(account.id)
                throw SessionRecoveryError.loginRejected
            case .api:
                pausedAccounts.insert(account.id)
                throw SessionRecoveryError.loginRejected
            default:
                throw error
            }
        }
    }
}
