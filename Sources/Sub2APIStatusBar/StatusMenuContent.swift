import AppKit
import SwiftUI
import Sub2APIStatusCore

@MainActor
struct StatusMenuContent: View {
    @ObservedObject var model: MonitorViewModel

    private var snapshot: MonitorSnapshot { model.snapshot }
    private var subscriptions: [SubscriptionSummaryItem] {
        snapshot.subscriptionSummary?.subscriptions ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            Divider()

            if snapshot.connected {
                quotaSection(for: quotaWindow(.daily))
                quotaSection(for: quotaWindow(.weekly))
                quotaSection(for: quotaWindow(.monthly))

                Divider()

                costSection
            } else {
                disconnectedSection
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(width: 302.4, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                providerIcon

                Text(providerLabel)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary.opacity(0.72))

                if usernameLabel != providerLabel {
                    accountSelector
                }
            }
            .lineLimit(1)
            .truncationMode(.middle)
            .layoutPriority(1)

            Spacer(minLength: 4)

            Button {
                model.refresh()
            } label: {
                HStack(spacing: 4) {
                    if model.isRefreshing {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                    }

                    Text(updatedText)
                        .font(.footnote)
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.isRefreshing)
            .help("Refresh usage")
        }
    }

    @ViewBuilder
    private var providerIcon: some View {
        if let url = Bundle.main.url(forResource: "ProviderIcon-codex", withExtension: "svg"),
           let image = NSImage(contentsOf: url) {
            let _ = image.isTemplate = true
            Image(nsImage: image)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 13, height: 13)
                .foregroundStyle(.primary.opacity(0.85))
        } else {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.85))
        }
    }

    @ViewBuilder
    private var accountSelector: some View {
        if model.config.accounts.isEmpty {
            accountLabel
        } else {
            Menu {
                ForEach(model.config.accounts) { account in
                    Button {
                        model.selectAccount(account)
                    } label: {
                        if account.id == model.config.selectedAccountID {
                            Label(account.displayName, systemImage: "checkmark")
                        } else {
                            Text(account.displayName)
                        }
                    }
                }
            } label: {
                accountLabel
            }
            .menuStyle(.borderlessButton)
            .tint(.primary.opacity(0.72))
            .fixedSize()
            .help("Switch account")
        }
    }

    private var accountLabel: some View {
        HStack(spacing: 3) {
            Image(systemName: "person")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.primary.opacity(0.85))
            Text(usernameLabel)
                .font(.footnote)
                .lineLimit(1)
                .foregroundStyle(.primary.opacity(0.72))
        }
    }

    private func quotaSection(for window: QuotaMenuWindow) -> some View {
        UsageMetricSection(
            title: window.title,
            progress: window.progress,
            tint: progressColor(window.usedProgress),
            markers: menuBarMarkers,
            leadingText: window.percentText,
            trailingText: window.amountText,
            detailText: window.resetText
        )
    }

    private var costSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            usageSummaryRow(
                "Today",
                cost: snapshot.stats.map { StatusFormatters.currency($0.todayActualCost) } ?? "--",
                requests: snapshot.stats?.todayRequests,
                tokens: snapshot.stats?.todayTokens
            )
            usageSummaryRow(
                "Total",
                cost: snapshot.stats.map { StatusFormatters.currency($0.totalActualCost) } ?? "--",
                requests: snapshot.stats?.totalRequests,
                tokens: snapshot.stats?.totalTokens
            )
            summaryRow(title: "Expires", value: expiryText)
        }
    }

    private func usageSummaryRow(
        _ title: String,
        cost: String,
        requests: Int64?,
        tokens: Int64?
    ) -> some View {
        let value = if let requests, let tokens {
            "\(StatusFormatters.menuBarCount(requests)) req · \(StatusFormatters.compactNumber(tokens)) token · \(cost)"
        } else {
            cost
        }
        return summaryRow(title: title, value: value)
    }

    private func summaryRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(title):")
            Text(value)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .font(.footnote)
    }

    private var disconnectedSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Not connected")

            Text(snapshot.message ?? "Add an account to view usage.")
                .foregroundStyle(.secondary)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var providerLabel: String {
        if let active = subscriptions.first(where: { $0.status == "active" }), !active.groupName.isEmpty {
            return active.groupName
        }
        if let first = subscriptions.first, !first.groupName.isEmpty {
            return first.groupName
        }
        if let host = URL(string: model.config.baseURL)?.host, !host.isEmpty {
            return host
        }
        return "Provider"
    }

    private var usernameLabel: String {
        if let username = snapshot.currentUser?.username, !username.isEmpty {
            return username
        }
        if let selected = model.config.selectedAccount {
            return selected.displayName
        }
        if let email = snapshot.currentUser?.email, !email.isEmpty {
            return email
        }
        return snapshot.connected ? "Connected" : "Offline"
    }

    private var updatedText: String {
        guard let updatedAt = snapshot.lastUpdatedAt else {
            return model.isRefreshing ? "updating" : "waiting"
        }

        let elapsed = max(model.now.timeIntervalSince(updatedAt), 0)
        if elapsed < 60 {
            return model.isRefreshing ? "updating" : "now"
        }
        return "\(StatusFormatters.duration(seconds: elapsed)) ago"
    }

    private var expiryText: String {
        if let value = subscriptions.compactMap(\.expiresAt).sorted().first {
            return String(value.prefix(10))
        }
        if let days = subscriptions.compactMap(\.daysRemaining).min() {
            return days <= 0 ? "Today" : "in \(days)d"
        }
        return "--"
    }

    private var menuBarMarkers: [Double] {
        switch model.config.menuBarUsageDisplay {
        case .remaining:
            [0.25, 0.5]
        case .used:
            [0.5, 0.75]
        }
    }

    private func quotaWindow(_ period: QuotaPeriod) -> QuotaMenuWindow {
        let candidates = subscriptions.map { subscription in
            QuotaMenuWindow(
                title: period.title,
                usedProgress: period.progress(in: subscription) ?? 0,
                hasValue: period.progress(in: subscription) != nil,
                used: period.used(in: subscription),
                limit: period.limit(in: subscription),
                resetInSeconds: period.reset(in: subscription),
                display: model.config.menuBarUsageDisplay
            )
        }

        return candidates.max { lhs, rhs in
            lhs.usedProgress < rhs.usedProgress
        } ?? QuotaMenuWindow(
            title: period.title,
            usedProgress: 0,
            hasValue: false,
            used: nil,
            limit: nil,
            resetInSeconds: nil,
            display: model.config.menuBarUsageDisplay
        )
    }

    private func progressColor(_ progress: Double) -> Color {
        if progress >= 0.95 {
            return .red
        }
        if progress >= 0.8 {
            return .orange
        }
        return .accentColor
    }
}

private enum QuotaPeriod {
    case daily
    case weekly
    case monthly

    var title: String {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        }
    }

    func progress(in subscription: SubscriptionSummaryItem) -> Double? {
        switch self {
        case .daily: subscription.dailyProgress
        case .weekly: subscription.weeklyProgress
        case .monthly: subscription.monthlyProgress
        }
    }

    func reset(in subscription: SubscriptionSummaryItem) -> Double? {
        switch self {
        case .daily: subscription.dailyResetInSeconds
        case .weekly: subscription.weeklyResetInSeconds
        case .monthly: subscription.monthlyResetInSeconds
        }
    }

    func used(in subscription: SubscriptionSummaryItem) -> Double? {
        switch self {
        case .daily: subscription.dailyUsedUSD
        case .weekly: subscription.weeklyUsedUSD
        case .monthly: subscription.monthlyUsedUSD
        }
    }

    func limit(in subscription: SubscriptionSummaryItem) -> Double? {
        switch self {
        case .daily: subscription.dailyLimitUSD
        case .weekly: subscription.weeklyLimitUSD
        case .monthly: subscription.monthlyLimitUSD
        }
    }
}

private struct QuotaMenuWindow {
    let title: String
    let usedProgress: Double
    let hasValue: Bool
    let used: Double?
    let limit: Double?
    let resetInSeconds: Double?
    let display: MenuBarUsageDisplay

    var progress: Double {
        let clamped = min(max(usedProgress, 0), 1)
        return display == .remaining ? 1 - clamped : clamped
    }

    var percentText: String {
        guard hasValue else {
            return "Usage unavailable"
        }
        return "\(StatusFormatters.percent(progress)) \(display.rawValue)"
    }

    var amountText: String? {
        guard let used, let limit else {
            return nil
        }
        return "\(StatusFormatters.currency(used)) / \(StatusFormatters.currency(limit))"
    }

    var resetText: String? {
        resetInSeconds.map { "Resets in \(StatusFormatters.duration(seconds: $0))" }
    }
}

private struct QuotaProgressBar: View {
    let progress: Double
    let tint: Color
    let markers: [Double]
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Canvas { context, size in
            let scale = max(displayScale, 1)
            let rect = CGRect(origin: .zero, size: size)
            let radius = size.height / 2
            let track = Path(roundedRect: rect, cornerRadius: radius)
            let clampedProgress = min(max(progress, 0), 1)
            let fillWidth = size.width * clampedProgress

            context.clip(to: Path(rect))
            context.fill(track, with: .color(.primary.opacity(0.14)))

            if fillWidth > 0 {
                let fillRect = CGRect(x: 0, y: 0, width: min(fillWidth, size.width), height: size.height)
                context.fill(
                    Path(roundedRect: fillRect, cornerRadius: radius),
                    with: .color(tint)
                )
            }

            for marker in visibleMarkers(markers, progress: clampedProgress) {
                let centerX = aligned(size.width * marker, scale: scale)
                let punchRect = CGRect(x: centerX - 2.5, y: 0, width: 5, height: size.height)
                let stripeWidth = max(1 / scale, 1)
                let stripeRect = CGRect(
                    x: aligned(centerX - stripeWidth / 2, scale: scale),
                    y: 0,
                    width: stripeWidth,
                    height: size.height
                )

                context.blendMode = .destinationOut
                context.fill(Path(punchRect), with: .color(.white.opacity(0.9)))
                context.blendMode = .normal
                context.fill(Path(stripeRect), with: .color(.primary.opacity(0.68)))
            }
        }
        .frame(height: 6)
        .accessibilityLabel("Quota usage")
        .accessibilityValue(StatusFormatters.percent(min(max(progress, 0), 1)))
    }

    private func visibleMarkers(_ values: [Double], progress: Double) -> [Double] {
        guard progress < 1 else {
            return []
        }
        return values.map { min(max($0, 0), 1) }.filter { $0 > 0 && $0 < 1 }
    }

    private func aligned(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        (value * scale).rounded() / scale
    }
}

private struct UsageMetricSection: View {
    let title: String
    let progress: Double
    let tint: Color
    let markers: [Double]
    let leadingText: String
    let trailingText: String?
    let detailText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)

            QuotaProgressBar(progress: progress, tint: tint, markers: markers)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(leadingText)
                    Spacer(minLength: 8)
                    if let trailingText {
                        Text(trailingText)
                    }
                }

                if let detailText {
                    HStack {
                        Spacer(minLength: 8)
                        Text(detailText)
                            .lineLimit(1)
                    }
                }
            }
            .foregroundStyle(.secondary)
            .font(.footnote)
        }
    }
}
