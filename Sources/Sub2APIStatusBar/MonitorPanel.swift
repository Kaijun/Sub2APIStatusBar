import SwiftUI
import Sub2APIStatusCore

struct MonitorPanel: View {
    @ObservedObject var model: MonitorViewModel
    @State private var showingSettings = false

    var body: some View {
        Group {
            if model.config.authToken.isEmpty {
                LoginPanel(model: model)
            } else {
                connectedPanel
            }
        }
        .frame(width: 400, height: 640)
        .background(PanelColors.background)
        .sheet(isPresented: $showingSettings) {
            SettingsView(model: model)
        }
    }

    private var connectedPanel: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                LazyVStack(spacing: 0) {
                    statusSummary

                    if model.snapshot.connected {
                        if let summary = model.snapshot.subscriptionSummary {
                            sectionDivider
                            quotaSection(summary)
                        }

                        if let stats = model.snapshot.stats {
                            sectionDivider
                            todaySection(stats)
                        }

                        if !usageInsights.items.isEmpty {
                            sectionDivider
                            UsageInsightsView(insights: usageInsights)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 13)
                        }

                        if let trend = model.snapshot.trend, !trend.isEmpty {
                            sectionDivider
                            trendSection(trend)
                        }

                        if let models = model.snapshot.modelDistribution, !models.isEmpty {
                            sectionDivider
                            ModelDistributionView(models: models)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 13)
                        }
                    }

                    if let updateInfo = model.updateInfo, updateInfo.isUpdateAvailable {
                        sectionDivider
                        UpdateAvailableBanner(info: updateInfo) {
                            model.openLatestRelease()
                        }
                        .padding(14)
                    }

                    if let message = model.snapshot.message, !message.isEmpty {
                        sectionDivider
                        MessageRow(message: message)
                            .padding(14)
                    }

                    if let suggestion = model.snapshotRecoverySuggestion {
                        RecoverySuggestionCard(suggestion: suggestion) { action in
                            model.performRecoveryAction(action)
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 14)
                    }

                    if let user = model.snapshot.currentUser {
                        sectionDivider
                        UserAccountCard(user: user)
                            .padding(14)
                    }
                }
            }

            footer
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ProviderMark(severity: severity)

            VStack(alignment: .leading, spacing: 2) {
                Text(activeAccountTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(accountDetail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if !model.config.accounts.isEmpty {
                AccountSwitcher(model: model)
            }

            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(model.isRefreshing ? .degrees(360) : .zero)
                    .animation(
                        model.isRefreshing
                            ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                            : .default,
                        value: model.isRefreshing
                    )
            }
            .disabled(model.isRefreshing)
            .buttonStyle(MenuIconButtonStyle())
            .help("Refresh")

            Button {
                model.settingsDraft = model.config
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(MenuIconButtonStyle())
            .help("Settings")
        }
        .padding(.horizontal, 12)
        .frame(height: 54)
        .background(PanelColors.chrome)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PanelColors.border)
                .frame(height: 1)
        }
    }

    private var statusSummary: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                    Text(statusLabel)
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(lastUpdatedText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(balanceText)
                    .font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("Balance")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }

    private func quotaSection(_ summary: SubscriptionSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            MenuSectionHeader(
                title: "Limits",
                trailing: "\(summary.activeCount) active"
            )

            ForEach(Array(summary.subscriptions.prefix(5).enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Divider()
                }
                SubscriptionQuotaCard(item: item)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }

    private func todaySection(_ stats: DashboardStats) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            MenuSectionHeader(title: "Today")

            HStack(spacing: 0) {
                CompactMetric(
                    title: "Spend",
                    value: StatusFormatters.preciseCurrency(stats.todayActualCost)
                )
                metricDivider
                CompactMetric(
                    title: "Tokens",
                    value: StatusFormatters.compactNumber(stats.todayTokens)
                )
                metricDivider
                CompactMetric(
                    title: "Requests",
                    value: StatusFormatters.menuBarCount(stats.todayRequests)
                )
            }

            HStack {
                Label("\(StatusFormatters.menuBarRate(stats.rpm)) RPM", systemImage: "speedometer")
                Spacer()
                Text(tokenBreakdown(input: stats.todayInputTokens, output: stats.todayOutputTokens))
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }

    private func trendSection(_ points: [TrendDataPoint]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MenuSectionHeader(title: "7-day usage")
            UsageTrendSection(state: UsageTrendDisplayState.make(points: points))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                model.openDashboard()
            } label: {
                Label("Open Dashboard", systemImage: "safari")
            }
            .buttonStyle(.borderless)
            .disabled(model.config.baseURL.isEmpty)

            Spacer()

            Menu {
                Button {
                    model.copySocialShareCard()
                } label: {
                    Label("Copy Share Card", systemImage: "square.and.arrow.up")
                }
                Button {
                    model.copyUsageReport()
                } label: {
                    Label("Copy Usage Report", systemImage: "doc.on.doc")
                }
                Button {
                    model.openSocialShareDraft()
                } label: {
                    Label("Draft Post", systemImage: "paperplane")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("More actions")

            Button {
                model.quit()
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(MenuIconButtonStyle())
            .help("Quit")
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
        .background(PanelColors.chrome)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(PanelColors.border)
                .frame(height: 1)
        }
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(PanelColors.border)
            .frame(height: 1)
            .padding(.leading, 14)
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(PanelColors.border)
            .frame(width: 1, height: 34)
    }

    private var activeAccountTitle: String {
        model.config.selectedAccount?.displayName ?? "Sub2API"
    }

    private var accountDetail: String {
        guard let account = model.config.selectedAccount else {
            return "Sub2API"
        }
        return account.email.isEmpty ? account.baseURL : account.email
    }

    private var balanceText: String {
        guard let balance = model.snapshot.currentUser?.balance else {
            return "--"
        }
        return StatusFormatters.currency(balance)
    }

    private var usageInsights: UsageInsights {
        UsageInsights.make(
            currentUser: model.snapshot.currentUser,
            stats: model.snapshot.stats,
            subscriptionSummary: model.snapshot.subscriptionSummary,
            trend: model.snapshot.trend,
            models: model.snapshot.modelDistribution,
            thresholds: model.config.insightThresholds
        )
    }

    private var severity: MonitorSeverity {
        model.snapshot.severity(now: model.now, refreshIntervalSeconds: model.config.refreshIntervalSeconds)
    }

    private var statusLabel: String {
        model.snapshot.statusLabel(now: model.now, refreshIntervalSeconds: model.config.refreshIntervalSeconds)
    }

    private var statusColor: Color {
        switch severity {
        case .healthy:
            .green
        case .warning:
            .orange
        case .error:
            .red
        }
    }

    private var lastUpdatedText: String {
        guard let date = model.snapshot.lastUpdatedAt else {
            return "Waiting for refresh"
        }
        let relative = date.formatted(.relative(presentation: .named))
        return model.snapshot.isStale(now: model.now, refreshIntervalSeconds: model.config.refreshIntervalSeconds)
            ? "Updated \(relative) - stale"
            : "Updated \(relative)"
    }

    private func tokenBreakdown(input: Int64, output: Int64) -> String {
        "In \(StatusFormatters.compactNumber(input)) / Out \(StatusFormatters.compactNumber(output))"
    }
}

struct ProviderMark: View {
    let severity: MonitorSeverity

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.07))
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: 30, height: 30)
    }

    private var tint: Color {
        switch severity {
        case .healthy:
            .green
        case .warning:
            .orange
        case .error:
            .red
        }
    }
}

struct MenuSectionHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct CompactMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MenuIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .frame(width: 28, height: 28)
            .background(
                Color.primary.opacity(configuration.isPressed ? 0.12 : 0.055),
                in: RoundedRectangle(cornerRadius: 6)
            )
            .contentShape(Rectangle())
    }
}

struct AccountSwitcher: View {
    @ObservedObject var model: MonitorViewModel

    var body: some View {
        Menu {
            ForEach(model.config.accounts) { account in
                Button {
                    model.selectAccount(account)
                } label: {
                    Label(
                        account.displayName,
                        systemImage: account.id == model.config.selectedAccountID
                            ? "checkmark.circle.fill"
                            : "person.crop.circle"
                    )
                }
            }
        } label: {
            Image(systemName: "person.2")
                .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Switch account")
    }
}
