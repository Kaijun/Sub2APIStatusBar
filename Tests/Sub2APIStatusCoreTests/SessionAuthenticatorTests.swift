import Foundation
import Testing
@testable import Sub2APIStatusCore

private struct TestCredentialStore: AccountCredentialStore {
    let credentials: [String: SavedLoginCredentials]

    func load(for accountID: String) throws -> SavedLoginCredentials? { credentials[accountID] }
    func save(_ credentials: SavedLoginCredentials, for accountID: String) throws {}
    func delete(for accountID: String) throws {}
}

private actor TestAuthenticationClient: SessionAuthenticationClient {
    var logins: [LoginRequest] = []
    var refreshes: [String] = []
    let failure: Sub2APIError?

    init(failure: Sub2APIError? = nil) { self.failure = failure }

    func login(email: String, password: String) async throws -> AuthResponse {
        logins.append(LoginRequest(email: email, password: password))
        if let failure { throw failure }
        return AuthResponse(accessToken: "new-access", refreshToken: nil, expiresIn: 60, tokenType: "Bearer", user: nil)
    }

    func refreshToken(_ refreshToken: String) async throws -> AuthResponse {
        refreshes.append(refreshToken)
        if let failure { throw failure }
        return AuthResponse(accessToken: "refreshed-access", refreshToken: "rotated-refresh", expiresIn: 60, tokenType: "Bearer", user: nil)
    }
}

private actor SuspendedLoginClient: SessionAuthenticationClient {
    private var pendingLogin: CheckedContinuation<AuthResponse, Error>?
    private var startWaiter: CheckedContinuation<Void, Never>?

    func login(email: String, password: String) async throws -> AuthResponse {
        try await withCheckedThrowingContinuation { continuation in
            pendingLogin = continuation
            startWaiter?.resume()
            startWaiter = nil
        }
    }

    func refreshToken(_ refreshToken: String) async throws -> AuthResponse {
        throw Sub2APIError.missingData
    }

    func waitForLogin() async {
        if pendingLogin != nil { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func rejectLogin() {
        pendingLogin?.resume(throwing: Sub2APIError.badStatus(401, "old password rejected"))
        pendingLogin = nil
    }
}

private func passwordAccount(id: String = "account-one", baseURL: String = "https://one.example.com") -> StoredAccount {
    StoredAccount(
        id: id, email: "user@example.com", baseURL: baseURL,
        authToken: "expired-access", automaticLoginEnabled: true
    )
}

private func sessionConfig(_ account: StoredAccount) -> AppConfig {
    AppConfig(
        baseURL: account.baseURL, authToken: account.authToken, refreshToken: account.refreshToken,
        accounts: [account], selectedAccountID: account.id
    )
}

private func savedLogin(for account: StoredAccount) -> SavedLoginCredentials {
    SavedLoginCredentials(baseURL: account.baseURL, email: account.email, password: "saved-secret")
}

@Test func passwordSessionRenewsWithoutRefreshToken() async throws {
    let account = passwordAccount()
    let authenticator = SessionAuthenticator(credentialStore: TestCredentialStore(credentials: [account.id: savedLogin(for: account)]))
    let client = TestAuthenticationClient()

    let response = try await authenticator.renewSession(config: sessionConfig(account), client: client)

    #expect(response?.accessToken == "new-access")
    #expect(response?.refreshToken == nil)
    let logins = await client.logins
    #expect(logins.count == 1)
    #expect(logins.first?.email == account.email)
    #expect(logins.first?.password == "saved-secret")
    #expect(await client.refreshes.isEmpty)
}

@Test func passwordSessionUsesLoginEvenWhenRefreshTokenExists() async throws {
    var account = passwordAccount()
    account.refreshToken = "unused-refresh"
    let authenticator = SessionAuthenticator(credentialStore: TestCredentialStore(credentials: [account.id: savedLogin(for: account)]))
    let client = TestAuthenticationClient()

    _ = try await authenticator.renewSession(config: sessionConfig(account), client: client)

    #expect(await client.logins.count == 1)
    #expect(await client.refreshes.isEmpty)
}

@Test func tokenOnlySessionKeepsRefreshTokenFlow() async throws {
    var account = passwordAccount()
    account.automaticLoginEnabled = false
    account.refreshToken = "old-refresh"
    let authenticator = SessionAuthenticator(credentialStore: TestCredentialStore(credentials: [:]))
    let client = TestAuthenticationClient()

    let response = try await authenticator.renewSession(config: sessionConfig(account), client: client)

    #expect(response?.accessToken == "refreshed-access")
    #expect(response?.refreshToken == "rotated-refresh")
    #expect(await client.refreshes == ["old-refresh"])
    #expect(await client.logins.isEmpty)
}

@Test func tokenOnlySessionWithoutRefreshTokenDoesNotSubmitPassword() async throws {
    var account = passwordAccount()
    account.automaticLoginEnabled = false
    let authenticator = SessionAuthenticator(credentialStore: TestCredentialStore(credentials: [account.id: savedLogin(for: account)]))
    let client = TestAuthenticationClient()

    let response = try await authenticator.renewSession(config: sessionConfig(account), client: client)

    #expect(response == nil)
    #expect(await client.logins.isEmpty)
    #expect(await client.refreshes.isEmpty)
}

@Test func savedPasswordCannotBeSentToChangedServerOrAccount() async {
    let account = passwordAccount()
    var changedServer = sessionConfig(account)
    changedServer.baseURL = "https://other.example.com"
    var changedAccount = sessionConfig(account)
    changedAccount.accounts[0].email = "different@example.com"

    for config in [changedServer, changedAccount] {
        let authenticator = SessionAuthenticator(credentialStore: TestCredentialStore(credentials: [account.id: savedLogin(for: account)]))
        let client = TestAuthenticationClient()
        await #expect(throws: SessionRecoveryError.savedLoginDoesNotMatch) {
            try await authenticator.renewSession(config: config, client: client)
        }
        #expect(await client.logins.isEmpty)
    }
}

@Test func missingSavedPasswordRequiresManualLogin() async {
    let account = passwordAccount()
    let authenticator = SessionAuthenticator(credentialStore: TestCredentialStore(credentials: [:]))
    let client = TestAuthenticationClient()

    await #expect(throws: SessionRecoveryError.savedLoginUnavailable) {
        try await authenticator.renewSession(config: sessionConfig(account), client: client)
    }
    #expect(await client.logins.isEmpty)
}

@Test func rejectedPasswordPausesAutomaticAttemptsUntilManualLogin() async throws {
    let account = passwordAccount()
    let authenticator = SessionAuthenticator(credentialStore: TestCredentialStore(credentials: [account.id: savedLogin(for: account)]))
    let rejected = TestAuthenticationClient(failure: .badStatus(401, "bad password"))
    let config = sessionConfig(account)
    let now = Date(timeIntervalSince1970: 1_000)

    await #expect(throws: SessionRecoveryError.loginRejected) {
        try await authenticator.renewSession(config: config, client: rejected, now: now)
    }
    await #expect(throws: SessionRecoveryError.loginPaused) {
        try await authenticator.renewSession(config: config, client: rejected, now: now.addingTimeInterval(3_600))
    }
    #expect(await rejected.logins.count == 1)

    await authenticator.reset(accountID: account.id)
    let accepted = TestAuthenticationClient()
    #expect(try await authenticator.renewSession(config: config, client: accepted, now: now)?.accessToken == "new-access")
}

@Test func transientLoginFailureWaitsBeforeRetrying() async throws {
    let account = passwordAccount()
    let authenticator = SessionAuthenticator(credentialStore: TestCredentialStore(credentials: [account.id: savedLogin(for: account)]))
    let client = TestAuthenticationClient(failure: .badStatus(503, "unavailable"))
    let config = sessionConfig(account)
    let now = Date(timeIntervalSince1970: 1_000)

    await #expect(throws: Sub2APIError.badStatus(503, "unavailable")) {
        try await authenticator.renewSession(config: config, client: client, now: now)
    }
    await #expect(throws: SessionRecoveryError.loginCooldown) {
        try await authenticator.renewSession(config: config, client: client, now: now.addingTimeInterval(15))
    }
    #expect(await client.logins.count == 1)
    let accepted = TestAuthenticationClient()
    _ = try await authenticator.renewSession(config: config, client: accepted, now: now.addingTimeInterval(61))
    #expect(await accepted.logins.count == 1)
}

@Test func staleAutomaticLoginCannotPauseUpdatedCredentials() async throws {
    let account = passwordAccount()
    let authenticator = SessionAuthenticator(credentialStore: TestCredentialStore(credentials: [account.id: savedLogin(for: account)]))
    let client = SuspendedLoginClient()
    let config = sessionConfig(account)
    let pending = Task { try await authenticator.renewSession(config: config, client: client) }
    await client.waitForLogin()
    await authenticator.reset(accountID: account.id)
    await client.rejectLogin()

    #expect(try await pending.value == nil)
    let accepted = TestAuthenticationClient()
    #expect(try await authenticator.renewSession(config: config, client: accepted)?.accessToken == "new-access")
}

@Test func legacyAccountConfigurationDoesNotEnablePasswordLogin() throws {
    let data = Data("""
    {"id":"legacy","baseURL":"https://one.example.com","authToken":"old-access"}
    """.utf8)
    let account = try JSONDecoder.sub2api.decode(StoredAccount.self, from: data)
    #expect(account.automaticLoginEnabled == false)
    #expect(account.authToken == "old-access")
}

@Test func passwordLoginSettingPersistsWithoutPasswordInConfig() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ConfigStore(configURL: directory.appendingPathComponent("config.json"))
    let account = passwordAccount()
    try store.save(sessionConfig(account))

    #expect(store.load().selectedAccount?.automaticLoginEnabled == true)
    let data = try Data(contentsOf: store.configurationFileURL)
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let accounts = try #require(json["accounts"] as? [[String: Any]])
    #expect(accounts.first?["password"] == nil)
    #expect(String(decoding: data, as: UTF8.self).contains("saved-secret") == false)
}

@Test func removingInactiveAccountPreservesActiveSession() {
    let active = passwordAccount()
    let other = passwordAccount(id: "account-two", baseURL: "https://two.example.com")
    var config = sessionConfig(active)
    config.accounts.append(other)

    config.removeAccount(id: other.id)

    #expect(config.accounts == [active])
    #expect(config.selectedAccountID == active.id)
    #expect(config.authToken == active.authToken)
    #expect(config.baseURL == active.baseURL)
}

@Test func removingActiveAccountSelectsRemainingAccountAndItsTokens() {
    let active = passwordAccount()
    var other = passwordAccount(id: "account-two", baseURL: "https://two.example.com")
    other.authToken = "other-access"
    other.refreshToken = "other-refresh"
    var config = sessionConfig(active)
    config.accounts.append(other)

    config.removeAccount(id: active.id)

    #expect(config.accounts == [other])
    #expect(config.selectedAccountID == other.id)
    #expect(config.authToken == other.authToken)
    #expect(config.refreshToken == other.refreshToken)
    #expect(config.baseURL == other.baseURL)
}

@Test func removingLastAccountClearsSessionAndUnknownRemovalDoesNothing() {
    let account = passwordAccount()
    var config = sessionConfig(account)
    config.removeAccount(id: "unknown")
    #expect(config == sessionConfig(account))

    config.removeAccount(id: account.id)

    #expect(config.accounts.isEmpty)
    #expect(config.selectedAccountID == nil)
    #expect(config.authToken.isEmpty)
    #expect(config.refreshToken.isEmpty)
}

@Test func removedAccountTokensDoNotReturnAfterConfigReload() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ConfigStore(configURL: directory.appendingPathComponent("config.json"))
    let account = passwordAccount()
    try store.save(sessionConfig(account))
    var config = store.load()
    config.removeAccount(id: account.id)
    try store.save(config)

    let loaded = store.load()
    #expect(loaded.accounts.isEmpty)
    #expect(loaded.authToken.isEmpty)
    #expect(loaded.refreshToken.isEmpty)
    #expect(loaded.selectedAccountID == nil)
}

@Test func addingManualTokenDoesNotOverwriteNamedAccount() {
    let account = passwordAccount()
    var config = sessionConfig(account)
    let newID = config.upsertAccount(name: "Manual Token", tokens: StoredAuthTokens(authToken: "manual-access"))
    #expect(newID != account.id)
    #expect(config.accounts.count == 2)
    #expect(config.accounts.first == account)
    #expect(config.selectedAccountID == newID)
}
