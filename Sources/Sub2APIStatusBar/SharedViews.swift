import AppKit
import SwiftUI
import Sub2APIStatusCore

struct SectionBlock<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content
        }
    }
}

enum PanelColors {
    static let background = Color(nsColor: .windowBackgroundColor)
    static let chrome = Color(nsColor: .controlBackgroundColor)
    static let backgroundTop = Color(nsColor: .windowBackgroundColor)
    static let backgroundMid = Color(nsColor: .windowBackgroundColor)
    static let backgroundBottom = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(
        light: Color(nsColor: .controlBackgroundColor),
        dark: Color(nsColor: .controlBackgroundColor)
    )
    static let elevatedSurface = Color(
        light: Color(nsColor: .controlBackgroundColor),
        dark: Color(nsColor: .controlBackgroundColor)
    )
    static let heroSurfaceStart = Color(
        light: Color(nsColor: .controlBackgroundColor),
        dark: Color(nsColor: .controlBackgroundColor)
    )
    static let heroSurfaceEnd = Color(
        light: Color(nsColor: .controlBackgroundColor),
        dark: Color(nsColor: .controlBackgroundColor)
    )
    static let softFill = Color(
        light: Color.primary.opacity(0.035),
        dark: Color.white.opacity(0.055)
    )
    static let border = Color(
        light: Color.primary.opacity(0.08),
        dark: Color.white.opacity(0.10)
    )
    static let mutedBorder = Color(
        light: Color.primary.opacity(0.05),
        dark: Color.white.opacity(0.07)
    )
}

struct PanelBackground: View {
    var body: some View {
        PanelColors.background
    }
}

extension Color {
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let bestMatch = appearance.bestMatch(from: [.darkAqua, .aqua])
            switch bestMatch {
            case .darkAqua:
                return NSColor(dark)
            default:
                return NSColor(light)
            }
        })
    }
}

struct StatusPill: View {
    let text: String
    let color: Color
    var systemImage: String?

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .bold))
            }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.13), in: Capsule())
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.callout)
    }
}

struct MessageRow: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(PanelColors.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(PanelColors.border, lineWidth: 1)
        )
    }
}

struct RecoverySuggestionCard: View {
    let suggestion: RecoverySuggestion
    let perform: (RecoveryActionKind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 3) {
                    Text(suggestion.title)
                        .font(.callout.weight(.semibold))
                    Text(suggestion.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                ForEach(suggestion.actions) { action in
                    Button {
                        perform(action.kind)
                    } label: {
                        Label(action.label, systemImage: action.systemImage)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(10)
        .background(PanelColors.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(PanelColors.border, lineWidth: 1)
        )
    }
}
