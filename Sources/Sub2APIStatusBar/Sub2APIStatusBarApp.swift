import AppKit
import SwiftUI
import Sub2APIStatusCore

@main
struct Sub2APIStatusBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusMenu = NSMenu()
    private let model = MonitorViewModel()

    private var settingsWindow: NSWindow?
    private var connectionWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if let button = statusItem.button {
            button.imagePosition = .imageLeading
            button.imageScaling = .scaleProportionallyDown
            button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        }

        statusMenu.autoenablesItems = false
        statusMenu.delegate = self
        statusItem.menu = statusMenu

        model.onSnapshotChange = { [weak self] snapshot in
            self?.updateStatusItem(snapshot)
        }
        updateStatusItem(model.snapshot)
        model.start()

        let opensMenuForVisualTesting = ProcessInfo.processInfo.environment["SUB2API_OPEN_POPOVER"] == "1"
            || ProcessInfo.processInfo.environment["SUB2API_OPEN_MENU"] == "1"
        let opensSettingsForVisualTesting = ProcessInfo.processInfo.environment["SUB2API_OPEN_SETTINGS"] == "1"
        if opensSettingsForVisualTesting {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
                self?.showSettings()
            }
        } else if opensMenuForVisualTesting {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
                self?.statusItem.button?.performClick(nil)
            }
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        statusMenu.removeAllItems()

        let contentItem = NSMenuItem()
        let contentView = NSHostingView(rootView: StatusMenuContent(model: model))
        contentView.frame = NSRect(x: 0, y: 0, width: 302.4, height: 1)
        contentView.layoutSubtreeIfNeeded()
        let fittingHeight = max(contentView.fittingSize.height, 80)
        contentView.frame = NSRect(x: 0, y: 0, width: 302.4, height: fittingHeight)
        contentItem.view = contentView
        statusMenu.addItem(contentItem)

        statusMenu.addItem(.separator())

        statusMenu.addItem(actionsMenuItem())

        statusMenu.addItem(.separator())

        statusMenu.addItem(menuItem("Settings...", symbol: "gearshape", action: #selector(showSettings), keyEquivalent: ","))
        statusMenu.addItem(menuItem("Quit", symbol: "power", action: #selector(quit), keyEquivalent: "q"))
    }

    private func accountMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Accounts", action: nil, keyEquivalent: "")
        item.image = menuImage(named: "person.crop.circle")

        let submenu = NSMenu()
        for account in model.config.accounts {
            let accountItem = NSMenuItem(title: account.displayName, action: #selector(selectAccount(_:)), keyEquivalent: "")
            accountItem.target = self
            accountItem.representedObject = account.id
            accountItem.state = account.id == model.config.selectedAccountID ? .on : .off
            submenu.addItem(accountItem)
        }
        submenu.addItem(.separator())
        submenu.addItem(menuItem("Manage Accounts...", symbol: "person.2", action: #selector(showSettings)))
        submenu.addItem(menuItem("Add Account...", symbol: "person.badge.plus", action: #selector(showConnection)))
        item.submenu = submenu
        return item
    }

    private func actionsMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Actions", action: nil, keyEquivalent: "")
        item.image = menuImage(named: "ellipsis.circle")

        let submenu = NSMenu()
        if model.config.accounts.isEmpty {
            submenu.addItem(menuItem("Add Account...", symbol: "person.badge.plus", action: #selector(showConnection)))
        } else {
            submenu.addItem(accountMenuItem())
        }
        submenu.addItem(menuItem("Usage Dashboard", symbol: "chart.bar.xaxis", action: #selector(openDashboard)))
        submenu.addItem(menuItem("Open Server", symbol: "safari", action: #selector(openServer)))
        submenu.addItem(.separator())
        submenu.addItem(menuItem("Refresh", symbol: "arrow.clockwise", action: #selector(refresh), keyEquivalent: "r"))
        submenu.addItem(.separator())
        submenu.addItem(menuItem("Copy Usage Report", symbol: "doc.on.doc", action: #selector(copyUsageReport)))
        submenu.addItem(menuItem("Copy Share Card", symbol: "rectangle.on.rectangle", action: #selector(copyShareCard)))
        submenu.addItem(menuItem("Draft Post", symbol: "square.and.pencil", action: #selector(draftPost)))
        item.submenu = submenu
        return item
    }

    private func menuItem(
        _ title: String,
        symbol: String,
        action: Selector,
        keyEquivalent: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.image = menuImage(named: symbol)
        return item
    }

    private func menuImage(named symbol: String) -> NSImage? {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        image?.isTemplate = true
        image?.size = NSSize(width: 16, height: 16)
        return image
    }

    @objc private func refresh() {
        model.refresh()
    }

    @objc private func selectAccount(_ sender: NSMenuItem) {
        guard let accountID = sender.representedObject as? String,
              let account = model.config.accounts.first(where: { $0.id == accountID }) else {
            return
        }
        model.selectAccount(account)
    }

    @objc private func openDashboard() {
        model.openDashboard()
    }

    @objc private func openServer() {
        model.openURL(model.config.baseURL)
    }

    @objc private func copyUsageReport() {
        model.copyUsageReport()
    }

    @objc private func copyShareCard() {
        model.copySocialShareCard()
    }

    @objc private func draftPost() {
        model.openSocialShareDraft()
    }

    @objc private func showSettings() {
        if let settingsWindow {
            present(settingsWindow)
            return
        }

        let rootView = SettingsView(model: model) { [weak self] in
            self?.settingsWindow?.close()
        }
        let window = makeWindow(
            title: "Sub2API Settings",
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 680),
            rootView: rootView
        )
        settingsWindow = window
        present(window)
    }

    @objc private func showConnection() {
        if let connectionWindow {
            present(connectionWindow)
            return
        }

        let window = makeWindow(
            title: "Connect Sub2API",
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 620),
            rootView: LoginPanel(model: model)
                .frame(width: 440, height: 620)
        )
        connectionWindow = window
        present(window)
    }

    private func makeWindow<Content: View>(
        title: String,
        contentRect: NSRect,
        rootView: Content
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: rootView)
        return window
    }

    private func present(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }
        if window === settingsWindow {
            settingsWindow = nil
        }
        if window === connectionWindow {
            connectionWindow = nil
        }
    }

    @objc private func quit() {
        model.quit()
    }

    private func updateStatusItem(_ snapshot: MonitorSnapshot) {
        guard let button = statusItem.button else {
            return
        }

        let statusLabel = snapshot.statusLabel(now: model.now, refreshIntervalSeconds: model.config.refreshIntervalSeconds)
        button.image = MenuBarMeterImage.make(
            levels: MenuBarUsageLevels(snapshot: snapshot),
            connected: snapshot.connected,
            display: model.config.menuBarUsageDisplay
        )
        button.title = ""

        if let stats = snapshot.stats, snapshot.connected {
            button.toolTip = "Sub2API \(statusLabel) - Today \(StatusFormatters.currency(stats.todayActualCost)), RPM \(String(format: "%.1f", stats.rpm))"
        } else {
            button.toolTip = "Sub2API \(statusLabel)"
        }
    }
}
