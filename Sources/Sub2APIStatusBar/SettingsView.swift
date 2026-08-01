import SwiftUI
import Sub2APIStatusCore

struct SettingsView: View {
    @ObservedObject var model: MonitorViewModel
    var onClose: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    init(model: MonitorViewModel, onClose: (() -> Void)? = nil) {
        self.model = model
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !model.config.accounts.isEmpty {
                        AccountSettingsSection(model: model)
                    }
                    GeneralSettingsSection(model: model)
                    AlertSettingsSection(model: model)
                    UpdateSettingsSection(model: model)
                    DiagnosticsSettingsSection(model: model)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let error = model.settingsError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.08))
            }

            Divider()
            footer
        }
        .frame(width: 520, height: 680)
        .background(PanelBackground())
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 34, height: 34)
                .background(Color.blue.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))

            Text("Settings")
                .font(.title2.bold())

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(PanelColors.elevatedSurface.opacity(0.88))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PanelColors.border)
                .frame(height: 1)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") {
                close()
            }
            Button("Save") {
                model.saveSettings()
                close()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(PanelColors.elevatedSurface.opacity(0.92))
    }

    private func close() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }
}

struct AccountSettingsSection: View {
    @ObservedObject var model: MonitorViewModel

    var body: some View {
        SettingsSection(title: "Accounts") {
            SettingsControlRow(title: "Active Account") {
                Picker("", selection: Binding(
                    get: { model.config.selectedAccountID ?? "" },
                    set: { id in
                        if let account = model.config.accounts.first(where: { $0.id == id }) {
                            model.selectAccount(account)
                            model.settingsDraft = model.config
                        }
                    }
                )) {
                    ForEach(model.config.accounts) { account in
                        Text(account.displayName).tag(account.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct GeneralSettingsSection: View {
    @ObservedObject var model: MonitorViewModel

    var body: some View {
        SettingsSection(title: "General") {
            VStack(spacing: 8) {
                SettingsControlRow(title: "Base URL") {
                    TextField("https://sub2api.example.com", text: $model.settingsDraft.baseURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                }

                SettingsControlRow(title: "Menu Bar Fill") {
                    Picker("", selection: $model.settingsDraft.menuBarUsageDisplay) {
                        ForEach(MenuBarUsageDisplay.allCases) { display in
                            Text(display.displayName).tag(display)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                }

                SettingsControlRow(title: "Menu Bar Rows") {
                    Picker("", selection: $model.settingsDraft.menuBarQuotaRows) {
                        ForEach(MenuBarQuotaRows.allCases) { rows in
                            Text(rows.displayName).tag(rows)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                }

                SettingsControlRow(title: "Startup") {
                    Toggle("Launch at login", isOn: Binding(
                        get: { model.launchAtLoginEnabled },
                        set: { model.setLaunchAtLogin($0) }
                    ))
                }

                SettingsControlRow(title: "Refresh") {
                    Slider(value: $model.settingsDraft.refreshIntervalSeconds, in: 5...300, step: 5)
                        .frame(maxWidth: .infinity)
                    Text("\(Int(model.settingsDraft.refreshIntervalSeconds))s")
                        .font(.callout.monospacedDigit())
                        .frame(width: 42, alignment: .trailing)
                }

                SettingsControlRow(title: "Bearer Token") {
                    SecureField("Token", text: $model.settingsDraft.authToken)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                }
            }

            if let error = model.launchAtLoginError {
                MessageRow(message: error)
            }
        }
    }
}

struct AlertSettingsSection: View {
    @ObservedObject var model: MonitorViewModel

    var body: some View {
        SettingsSection(title: "Alerts") {
            VStack(spacing: 8) {
                SettingsControlRow(title: "Notify") {
                    Toggle("Quota and usage warnings", isOn: $model.settingsDraft.insightAlertSettings.isEnabled)
                }

                SettingsControlRow(title: "Level") {
                    Picker("", selection: $model.settingsDraft.insightAlertSettings.minimumSeverity) {
                        Text("Warning").tag(MonitorSeverity.warning)
                        Text("Error only").tag(MonitorSeverity.error)
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(maxWidth: 320, alignment: .leading)
                }

                SettingsControlRow(title: "Quiet") {
                    Slider(value: $model.settingsDraft.insightAlertSettings.cooldownMinutes, in: 5...360, step: 5)
                        .frame(maxWidth: .infinity)
                    Text("\(Int(model.settingsDraft.insightAlertSettings.cooldownMinutes))m")
                        .font(.callout.monospacedDigit())
                        .frame(width: 48, alignment: .trailing)
                }

                InsightNotificationPermissionRow(model: model)
            }
        }
    }
}

struct InsightNotificationPermissionRow: View {
    @ObservedObject var model: MonitorViewModel

    private var summary: InsightNotificationPermissionSummary {
        InsightNotificationPermissionSummary.make(
            settings: model.settingsDraft.insightAlertSettings,
            authorization: model.notificationAuthorization
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 28, height: 28)
                .background(iconColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                Text(summary.title)
                    .font(.callout.weight(.semibold))
                Text(summary.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if let action = summary.action {
                Button(actionLabel(for: action)) {
                    perform(action)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .onAppear {
            model.refreshNotificationAuthorization()
        }
    }

    private var iconName: String {
        switch summary.action {
        case .requestPermission:
            "bell.badge"
        case .openSystemSettings:
            "bell.slash"
        case nil:
            model.settingsDraft.insightAlertSettings.isEnabled ? "bell.fill" : "bell"
        }
    }

    private var iconColor: Color {
        switch summary.action {
        case .requestPermission:
            .orange
        case .openSystemSettings:
            .red
        case nil:
            model.settingsDraft.insightAlertSettings.isEnabled ? .green : .secondary
        }
    }

    private func actionLabel(for action: InsightNotificationPermissionAction) -> String {
        switch action {
        case .requestPermission:
            "Enable"
        case .openSystemSettings:
            "Open Settings"
        }
    }

    private func perform(_ action: InsightNotificationPermissionAction) {
        switch action {
        case .requestPermission:
            model.requestNotificationAuthorization()
        case .openSystemSettings:
            model.openNotificationSettings()
        }
    }
}

struct SettingsControlRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PanelColors.elevatedSurface.opacity(0.88), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(PanelColors.border, lineWidth: 1)
        )
    }
}

struct DiagnosticsSettingsSection: View {
    @ObservedObject var model: MonitorViewModel

    var body: some View {
        SettingsSection(title: "Diagnostics") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button {
                        model.copySocialShareCard()
                    } label: {
                        Label("Copy Share Card", systemImage: "square.and.arrow.up")
                    }
                    .disabled(!model.snapshot.connected)

                    Button {
                        model.copyUsageReport()
                    } label: {
                        Label("Copy Usage Report", systemImage: "chart.line.text.clipboard")
                    }
                    .disabled(!model.snapshot.connected)
                }

                HStack {
                    Button {
                        model.copyDiagnostics()
                    } label: {
                        Label("Copy Diagnostics", systemImage: "doc.on.doc")
                    }

                    Button {
                        model.copySupportBundle()
                    } label: {
                        Label("Copy Support Bundle", systemImage: "doc.text")
                    }

                    Button {
                        model.revealConfigFile()
                    } label: {
                        Label("Show Config", systemImage: "folder")
                    }
                }
            }
            .buttonStyle(.borderless)
        }
    }
}

struct UpdateSettingsSection: View {
    @ObservedObject var model: MonitorViewModel

    var body: some View {
        SettingsSection(title: "Updates") {
            HStack {
                Spacer()
                if model.isCheckingForUpdates {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let updateInfo = model.updateInfo, updateInfo.isUpdateAvailable {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(updateInfo.statusText)
                            .font(.callout.weight(.medium))
                        Text(updateInfo.latestRelease.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } else if let message = model.updateStatusMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("Checks GitHub Releases for newer versions.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button {
                    model.checkForUpdates()
                } label: {
                    Label("Check Now", systemImage: "arrow.clockwise")
                }
                .disabled(model.isCheckingForUpdates)

                if model.updateInfo?.isUpdateAvailable == true {
                    Button {
                        model.openLatestRelease()
                    } label: {
                        Label("Open Release", systemImage: "safari")
                    }
                }
            }
            .buttonStyle(.borderless)
        }
    }
}

struct UpdateAvailableBanner: View {
    let info: UpdateInfo
    let openRelease: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(info.statusText)
                    .font(.callout.weight(.semibold))
                Text("Download the latest release from GitHub.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                openRelease()
            } label: {
                Image(systemName: "safari")
            }
            .buttonStyle(.borderless)
            .help("Open release")
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
