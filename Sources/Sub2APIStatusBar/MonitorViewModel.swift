import AppKit
import ServiceManagement
import Foundation
import Sub2APIStatusCore

@MainActor
final class MonitorViewModel: ObservableObject {
    @Published var config: AppConfig
    @Published var snapshot: MonitorSnapshot
    @Published var isRefreshing = false
    @Published var isLoggingIn = false
    @Published var loginEmail = ""
    @Published var loginPassword = ""
    @Published var loginBaseURL = ""
    @Published var manualAuthToken = ""
    @Published var remembersPassword = false
    @Published var settingsDraft: AppConfig
    @Published var settingsError: String?
    @Published var updateInfo: UpdateInfo?
    @Published var isCheckingForUpdates = false
    @Published var updateStatusMessage: String?
    @Published var launchAtLoginEnabled = false
    @Published var launchAtLoginError: String?
    @Published var focusesManualToken = false
    @Published var notificationAuthorization: InsightNotificationAuthorization = .notDetermined
    @Published var now = Date()

    var onSnapshotChange: ((MonitorSnapshot) -> Void)?

    private let store = ConfigStore()
    private let credentialStore = KeychainCredentialStore()
    private let sessionAuthenticator = SessionAuthenticator()
    private let updateChecker = GitHubUpdateChecker()
    private let insightNotifier = InsightNotifier()
    private var refreshTimer: Timer?
    private var clockTimer: Timer?

    init() {
        let loaded = store.load()
        config = loaded
        settingsDraft = loaded
        loginEmail = loaded.selectedAccount?.email ?? ""
        loginBaseURL = loaded.baseURL
        remembersPassword = loaded.selectedAccount?.automaticLoginEnabled ?? false
        snapshot = .idle(mode: loaded.monitorMode)
        launchAtLoginEnabled = Self.currentLaunchAtLoginState()
    }

    func start() {
        refresh()
        scheduleTimer()
        scheduleClock()
        checkForUpdates(silent: true)
        refreshNotificationAuthorization()
    }

    func refresh() {
        Task {
            await refreshNow()
        }
    }

    func refreshNow() async {
        guard !isRefreshing else {
            return
        }

        if config.authToken.isEmpty && config.selectedAccount?.automaticLoginEnabled != true {
            publish(.idle(mode: config.monitorMode))
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        let initialConfig = config
        var errorContext = initialConfig
        var renewedSession = false
        do {
            if initialConfig.authToken.isEmpty {
                guard try await renewAuthSession(for: initialConfig) else { return }
                renewedSession = true
            }
            let requestConfig = config
            errorContext = requestConfig
            do {
                let next = try await userSnapshot(client: Sub2APIClient(config: requestConfig))
                guard matchesAuthContext(requestConfig) else { return }
                publish(next)
            } catch {
                guard matchesAuthContext(requestConfig) else { return }
                guard let apiError = error as? Sub2APIError, apiError.isUnauthorized else { throw error }
                guard !renewedSession else { throw error }
                guard try await renewAuthSession(for: requestConfig) else { throw error }
                let retryConfig = config
                errorContext = retryConfig
                let next = try await userSnapshot(client: Sub2APIClient(config: retryConfig))
                guard matchesAuthContext(retryConfig) else { return }
                publish(next)
            }
        } catch {
            if matchesAuthContext(errorContext) {
                publishDisconnected(error)
            }
        }
    }

    private func userSnapshot(client: Sub2APIClient) async throws -> MonitorSnapshot {
        let currentUser = try await Self.optionalAuthenticated { try await client.currentUser() }
        async let summaryTask = client.subscriptionSummary()
        async let statsTask = Self.optionalAuthenticated { try await client.usageDashboardStats() }
        let range = Self.lastSevenDayRange()
        async let trendTask = Self.optionalAuthenticated {
            try await client.usageDashboardTrend(startDate: range.start, endDate: range.end, granularity: "day")
        }
        async let modelsTask = Self.optionalAuthenticated {
            try await client.usageDashboardModels(startDate: range.start, endDate: range.end)
        }

        let summary = try await summaryTask
        let stats = try await statsTask
        let trend = try await trendTask
        let models = try await modelsTask
        return MonitorSnapshot(
            mode: .user,
            connected: true,
            currentUser: currentUser?.user,
            stats: stats,
            trend: trend?.trend,
            modelDistribution: models?.models,
            realtime: nil,
            accountHealth: nil,
            subscriptionSummary: summary,
            lastUpdatedAt: Date(),
            message: nil
        )
    }

    nonisolated private static func optionalAuthenticated<Value: Sendable>(
        _ operation: @Sendable () async throws -> Value
    ) async throws -> Value? {
        do {
            return try await operation()
        } catch let error as Sub2APIError where error.isUnauthorized {
            throw error
        } catch {
            return nil
        }
    }

    private func matchesAuthContext(_ expected: AppConfig) -> Bool {
        config.selectedAccountID == expected.selectedAccountID
            && config.baseURL == expected.baseURL
            && config.authToken == expected.authToken
            && config.refreshToken == expected.refreshToken
            && config.selectedAccount?.automaticLoginEnabled == expected.selectedAccount?.automaticLoginEnabled
    }

    private func renewAuthSession(for expected: AppConfig) async throws -> Bool {
        guard matchesAuthContext(expected) else { return false }
        var refreshConfig = expected
        refreshConfig.authToken = ""
        guard let response = try await sessionAuthenticator.renewSession(
            config: expected,
            client: Sub2APIClient(config: refreshConfig)
        ), matchesAuthContext(expected) else { return false }
        var next = config
        next.authToken = response.accessToken
        next.refreshToken = response.refreshToken ?? (expected.selectedAccount?.automaticLoginEnabled == true ? "" : expected.refreshToken)
        try store.save(next)
        let loaded = store.load()
        config = loaded
        syncAccountSettings()
        return true
    }

    private func publishDisconnected(_ error: Error) {
        publish(MonitorSnapshot(
            mode: config.monitorMode,
            connected: false,
            stats: nil,
            realtime: nil,
            accountHealth: nil,
            subscriptionSummary: nil,
            lastUpdatedAt: snapshot.lastUpdatedAt,
            message: error.localizedDescription
        ))
    }

    @discardableResult
    func saveSettings() -> Bool {
        settingsError = nil
        var next = settingsDraft
        next.normalize()
        do {
            try store.save(next)
            let loaded = store.load()
            config = loaded
            settingsDraft = loaded
            scheduleTimer()
            refreshNotificationAuthorization()
            onSnapshotChange?(snapshot)
            refresh()
            return true
        } catch {
            settingsError = error.localizedDescription
            return false
        }
    }

    private func syncAccountSettings() {
        settingsDraft.baseURL = config.baseURL
        settingsDraft.authToken = config.authToken
        settingsDraft.refreshToken = config.refreshToken
        settingsDraft.accounts = config.accounts
        settingsDraft.selectedAccountID = config.selectedAccountID
    }

    func disconnect() {
        guard let account = config.selectedAccount else { return }
        removeAccount(account)
    }

    func removeAccount(_ account: StoredAccount) {
        guard config.accounts.contains(where: { $0.id == account.id }) else { return }
        settingsError = nil
        var next = config
        let wasActive = next.selectedAccountID == account.id
        next.removeAccount(id: account.id)
        do {
            try credentialStore.delete(for: account.id)
            try store.save(next)
            let loaded = store.load()
            config = loaded
            syncAccountSettings()
            loginEmail = loaded.selectedAccount?.email ?? ""
            loginBaseURL = loaded.baseURL
            loginPassword = ""
            manualAuthToken = ""
            remembersPassword = loaded.selectedAccount?.automaticLoginEnabled ?? false
            if wasActive {
                publish(.idle(mode: loaded.monitorMode))
                refresh()
            }
        } catch {
            settingsError = error.localizedDescription
        }
    }

    func selectAccount(_ account: StoredAccount) {
        settingsError = nil
        var next = config
        let tokens = store.loadTokens(for: account.id)
        next.selectAccount(id: account.id, tokens: tokens)
        do {
            try store.save(next)
            let loaded = store.load()
            config = loaded
            syncAccountSettings()
            loginEmail = loaded.selectedAccount?.email ?? ""
            loginBaseURL = loaded.baseURL
            loginPassword = ""
            manualAuthToken = ""
            remembersPassword = loaded.selectedAccount?.automaticLoginEnabled ?? false
            publish(.idle(mode: loaded.monitorMode))
            refresh()
        } catch {
            settingsError = error.localizedDescription
        }
    }

    func loginAndSave() {
        guard !isLoggingIn else { return }
        settingsError = nil
        var draft = config
        draft.baseURL = loginBaseURL
        draft.authToken = ""
        draft.normalize()
        let email = loginEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = loginPassword
        let remember = remembersPassword
        guard LoginFormState(baseURL: draft.baseURL, email: email, password: password).canSubmit else { return }
        let client = Sub2APIClient(config: draft)
        let originalContext = config
        isLoggingIn = true
        Task {
            defer { isLoggingIn = false }
            do {
                let response = try await client.login(email: email, password: password)
                guard matchesAuthContext(originalContext) else {
                    settingsError = "The active account changed during login. Please sign in again."
                    return
                }
                let tokens = StoredAuthTokens(authToken: response.accessToken, refreshToken: response.refreshToken ?? "")
                let displayName = response.user?.username ?? email
                var next = config
                let accountID = next.upsertAccount(
                    name: displayName,
                    email: response.user?.email ?? email,
                    baseURL: draft.baseURL,
                    tokens: tokens
                )
                if remember {
                    try credentialStore.save(
                        SavedLoginCredentials(baseURL: draft.baseURL, email: response.user?.email ?? email, password: password),
                        for: accountID
                    )
                } else {
                    try credentialStore.delete(for: accountID)
                }
                if let index = next.accounts.firstIndex(where: { $0.id == accountID }) {
                    next.accounts[index].automaticLoginEnabled = remember
                }
                try store.save(next)
                config = store.load()
                syncAccountSettings()
                loginEmail = config.selectedAccount?.email ?? email
                loginBaseURL = config.baseURL
                remembersPassword = remember
                loginPassword = ""
                manualAuthToken = ""
                await sessionAuthenticator.reset(accountID: accountID)
                scheduleTimer()
                publish(.idle(mode: config.monitorMode))
                refresh()
            } catch {
                settingsError = error.localizedDescription
            }
        }
    }

    func saveManualToken() {
        guard !isLoggingIn else { return }
        settingsError = nil
        var next = config
        next.baseURL = loginBaseURL
        next.authToken = manualAuthToken
        next.normalize()
        guard next.apiBaseURL != nil, !next.authToken.isEmpty else {
            settingsError = "Enter a valid server URL and bearer token."
            return
        }
        let existing = next.accounts.first {
            $0.baseURL == next.baseURL && $0.authToken == next.authToken
        }
        // A new manually entered token has no known refresh token or account identity.
        next.refreshToken = existing?.refreshToken ?? ""
        let accountID = next.upsertAccount(
            name: existing?.name ?? "Manual Token",
            email: existing?.email ?? "",
            baseURL: next.baseURL,
            tokens: StoredAuthTokens(authToken: next.authToken, refreshToken: next.refreshToken)
        )
        do {
            try credentialStore.delete(for: accountID)
            if let index = next.accounts.firstIndex(where: { $0.id == accountID }) {
                next.accounts[index].automaticLoginEnabled = false
            }
            try store.save(next)
            config = store.load()
            syncAccountSettings()
            loginEmail = config.selectedAccount?.email ?? ""
            loginBaseURL = config.baseURL
            loginPassword = ""
            manualAuthToken = ""
            remembersPassword = false
            scheduleTimer()
            publish(.idle(mode: config.monitorMode))
            refresh()
        } catch {
            settingsError = error.localizedDescription
        }
    }

    func forgetSavedPassword() {
        guard let accountID = config.selectedAccountID else { return }
        settingsError = nil
        do {
            try credentialStore.delete(for: accountID)
            var next = config
            if let index = next.accounts.firstIndex(where: { $0.id == accountID }) {
                next.accounts[index].automaticLoginEnabled = false
            }
            try store.save(next)
            config = store.load()
            syncAccountSettings()
            remembersPassword = false
            loginPassword = ""
        } catch {
            settingsError = error.localizedDescription
        }
    }

    func openDashboard() {
        openURL(config.baseURL)
    }

    func checkForUpdates(silent: Bool = false) {
        Task {
            await checkForUpdatesNow(silent: silent)
        }
    }

    func checkForUpdatesNow(silent: Bool = false) async {
        guard !isCheckingForUpdates else {
            return
        }

        isCheckingForUpdates = true
        if !silent {
            updateStatusMessage = nil
        }
        defer { isCheckingForUpdates = false }

        do {
            let info = try await updateChecker.check(currentVersion: currentAppVersion)
            updateInfo = info
            if info.isUpdateAvailable || !silent {
                updateStatusMessage = info.statusText
            }
        } catch {
            if !silent {
                updateStatusMessage = error.localizedDescription
            }
        }
    }

    func openLatestRelease() {
        if let releaseURL = updateInfo?.latestRelease.releaseURL {
            NSWorkspace.shared.open(releaseURL)
            return
        }
        openURL("https://github.com/\(AppBuildInfo.repositoryOwner)/\(AppBuildInfo.repositoryName)/releases")
    }

    func openURL(_ value: String) {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginEnabled = Self.currentLaunchAtLoginState()
        } catch {
            launchAtLoginEnabled = Self.currentLaunchAtLoginState()
            launchAtLoginError = error.localizedDescription
        }
    }

    func copyDiagnostics() {
        let report = DiagnosticReport.make(
            config: config,
            snapshot: snapshot,
            appVersion: currentAppVersion,
            notificationAuthorization: notificationAuthorization
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        updateStatusMessage = "Diagnostics copied."
    }

    func copySupportBundle() {
        let report = SupportBundleReport.make(
            config: config,
            snapshot: snapshot,
            appVersion: currentAppVersion
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        updateStatusMessage = "Support bundle copied."
    }

    func copyUsageReport() {
        let report = UsageReport.make(
            config: config,
            snapshot: snapshot,
            now: now
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        updateStatusMessage = "Usage report copied."
    }

    func copySocialShareCard() {
        let summary = SocialShareSummary.make(
            config: config,
            snapshot: snapshot,
            now: now
        )
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let image = SocialShareCardRenderer.image(for: summary) {
            pasteboard.writeObjects([image, NSString(string: summary.shareText)])
            updateStatusMessage = "Share card copied."
        } else {
            pasteboard.setString(summary.shareText, forType: .string)
            updateStatusMessage = "Share text copied."
        }
    }

    func openSocialShareDraft() {
        let summary = SocialShareSummary.make(
            config: config,
            snapshot: snapshot,
            now: now
        )
        var components = URLComponents(string: "https://twitter.com/intent/tweet")
        components?.queryItems = [
            URLQueryItem(name: "text", value: summary.shareText),
        ]
        if let url = components?.url {
            NSWorkspace.shared.open(url)
        }
    }

    func revealConfigFile() {
        NSWorkspace.shared.activateFileViewerSelecting([store.configurationFileURL])
    }

    func refreshNotificationAuthorization() {
        Task {
            notificationAuthorization = await insightNotifier.authorization()
        }
    }

    func requestNotificationAuthorization() {
        Task {
            notificationAuthorization = await insightNotifier.requestAuthorization()
        }
    }

    func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    func quit() {
        NSApp.terminate(nil)
    }

    var loginRecoverySuggestion: RecoverySuggestion {
        RecoverySuggestion.make(
            message: settingsError,
            hasBaseURL: !loginBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            hasToken: !manualAuthToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
    }

    var snapshotRecoverySuggestion: RecoverySuggestion? {
        guard !snapshot.connected else {
            return nil
        }
        return RecoverySuggestion.make(
            message: snapshot.message,
            hasBaseURL: !config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            hasToken: !config.authToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
    }

    func performRecoveryAction(_ action: RecoveryActionKind) {
        switch action {
        case .enterURL:
            loginBaseURL = loginBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        case .openServer:
            openURL(loginBaseURL.isEmpty ? config.baseURL : loginBaseURL)
        case .login:
            loginPassword = ""
        case .replaceToken:
            focusesManualToken = true
        case .retry:
            refresh()
        }
    }

    private func publish(_ next: MonitorSnapshot) {
        now = Date()
        snapshot = next
        onSnapshotChange?(next)
        notifyIfNeeded(for: next)
    }

    private func notifyIfNeeded(for snapshot: MonitorSnapshot) {
        guard snapshot.connected else {
            return
        }

        let insights = UsageInsights.make(
            currentUser: snapshot.currentUser,
            stats: snapshot.stats,
            subscriptionSummary: snapshot.subscriptionSummary,
            trend: snapshot.trend,
            models: snapshot.modelDistribution,
            thresholds: config.insightThresholds
        )
        insightNotifier.handle(insights: insights, settings: config.insightAlertSettings)
    }

    private var currentAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? AppBuildInfo.fallbackVersion
    }

    private func scheduleTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: config.refreshIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    private func scheduleClock() {
        clockTimer?.invalidate()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else {
                    return
                }
                self.now = Date()
                self.onSnapshotChange?(self.snapshot)
                self.notifyIfStale(self.snapshot, now: self.now)
            }
        }
    }

    private func notifyIfStale(_ snapshot: MonitorSnapshot, now: Date) {
        insightNotifier.handleStaleSnapshot(
            snapshot,
            refreshIntervalSeconds: config.refreshIntervalSeconds,
            settings: config.insightAlertSettings,
            now: now
        )
    }

    private static func lastSevenDayRange() -> (start: String, end: String) {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return (formatter.string(from: start), formatter.string(from: today))
    }

    private static func currentLaunchAtLoginState() -> Bool {
        SMAppService.mainApp.status == .enabled
    }
}
