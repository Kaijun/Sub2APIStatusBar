import AppKit
import SwiftUI
import Sub2APIStatusCore

struct MetricItem: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let caption: String?
    let systemImage: String?
    let tint: Color

    init(title: String, value: String, caption: String? = nil, systemImage: String? = nil, tint: Color = .accentColor) {
        self.title = title
        self.value = value
        self.caption = caption
        self.systemImage = systemImage
        self.tint = tint
    }
}

struct UserAccountCard: View {
    let user: CurrentUser

    private var displayName: String {
        guard let username = user.username, !username.isEmpty else {
            return user.email
        }
        return username
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(user.email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer()

            if let status = user.status, !status.isEmpty {
                StatusPill(
                    text: status.capitalized,
                    color: status.lowercased() == "active" ? .green : .secondary
                )
            }
        }
    }
}

struct MetricGrid: View {
    let items: [MetricItem]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(items) { item in
                HStack(spacing: 10) {
                    if let systemImage = item.systemImage {
                        SafeSystemImage(systemName: systemImage)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(item.tint)
                            .frame(width: 34, height: 34)
                            .background(item.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(item.value)
                            .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        if let caption = item.caption {
                            Text(caption)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(PanelColors.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(PanelColors.border, lineWidth: 1)
                )
            }
        }
    }
}

private struct SafeSystemImage: View {
    let systemName: String
    var fallbackName = "circle.grid.3x3.fill"

    var body: some View {
        if let image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: fallbackName, accessibilityDescription: nil) {
            Image(nsImage: image)
                .renderingMode(.template)
        } else {
            Image(systemName: "questionmark.circle")
        }
    }
}

struct UsageInsightsView: View {
    let insights: UsageInsights

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text("Signals")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text(insights.headline)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            VStack(spacing: 0) {
                ForEach(Array(insights.items.prefix(4).enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Divider()
                    }
                    HStack(spacing: 8) {
                        SafeSystemImage(systemName: iconName(for: item.kind))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(color(for: item.severity))
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                            Text(item.detail)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }

                        Spacer(minLength: 8)

                        Text(item.value)
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .foregroundStyle(color(for: item.severity))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(minHeight: 43)
                }
            }
        }
    }

    private func iconName(for kind: UsageInsightKind) -> String {
        switch kind {
        case .quota:
            "gauge.with.dots.needle.67percent"
        case .balance:
            "banknote"
        case .budget:
            "calendar.badge.clock"
        case .spend:
            "dollarsign.arrow.circlepath"
        case .trend:
            "chart.line.uptrend.xyaxis"
        case .modelMix:
            "square.stack.3d.up"
        case .performance:
            "speedometer"
        }
    }

    private func color(for severity: MonitorSeverity) -> Color {
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
