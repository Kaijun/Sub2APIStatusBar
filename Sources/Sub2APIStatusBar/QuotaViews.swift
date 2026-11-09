import SwiftUI
import Sub2APIStatusCore

struct SubscriptionQuotaCard: View {
    let item: SubscriptionSummaryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Circle()
                    .fill(item.status == "active" ? Color.green : Color.secondary)
                    .frame(width: 6, height: 6)
                Text(item.groupName)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if let days = item.daysRemaining {
                    Text("\(days)d left")
                        .font(.system(size: 10))
                        .foregroundStyle(days <= 3 ? .orange : .secondary)
                }
            }

            ForEach(quotaWindows, id: \.title) { window in
                QuotaProgressRow(window: window)
            }
        }
    }

    private var quotaWindows: [QuotaWindowDisplay] {
        [
            QuotaWindowDisplay(
                title: "Daily",
                used: item.dailyUsedUSD,
                limit: item.dailyLimitUSD,
                progress: item.dailyProgress,
                resetInSeconds: item.dailyResetInSeconds
            ),
            QuotaWindowDisplay(
                title: "Weekly",
                used: item.weeklyUsedUSD,
                limit: item.weeklyLimitUSD,
                progress: item.weeklyProgress,
                resetInSeconds: item.weeklyResetInSeconds
            ),
        ]
    }

}

struct QuotaProgressRow: View {
    let window: QuotaWindowDisplay

    private var tint: Color {
        switch window.severity {
        case .healthy:
            .green
        case .warning:
            .orange
        case .error:
            .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(window.percentText)
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(tint)
                    .frame(width: 34, alignment: .trailing)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.10))
                    Capsule()
                        .fill(tint)
                        .frame(width: max(3, proxy.size.width * window.normalizedProgress))
                }
            }
            .frame(height: 4)

            HStack {
                Text(window.amountText)
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer()
                if let resetText = window.resetText {
                    Text(resetText)
                }
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(window.title) quota \(window.percentText), \(window.remainingText)")
        }
    }
}
