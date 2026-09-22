import AppKit

private enum MenuStatus {
    case idle
    case success(String)
    case failure(String)

    func detailMenuText(timestamp: String) -> String {
        switch self {
        case .idle:
            return "Status: Ready (\(timestamp))"
        case .success:
            return "Status: \(detailText) (\(timestamp))"
        case .failure:
            return "Status: \(detailText) (\(timestamp))"
        }
    }

    private var detailText: String {
        switch self {
        case .idle:
            return "Ready"
        case .success(let detail):
            return detail
        case .failure(let detail):
            return detail
        }
    }
}

@MainActor
final class WakeFoxApp: NSObject, NSApplicationDelegate {
    private static let statusSymbolName = "network"

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let settingsManager: SettingsManager
    private let wakeSender: WakeOnLanSending
    private let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter
    }()
    private var settingsWindow: SettingsWindow?
    private var currentStatus: MenuStatus = .idle
    private weak var statusDetailItem: NSMenuItem?

    init(settingsManager: SettingsManager = .shared, wakeSender: WakeOnLanSending = WakeOnLanSender()) {
        self.settingsManager = settingsManager
        self.wakeSender = wakeSender
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyStatus(.idle)
        constructMenu()

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SettingsChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.constructMenu()
            }
        }
    }

    private func constructMenu() {
        let menu = NSMenu()
        let interfaces = settingsManager.getInterfaces()
        let timestamp = timestampFormatter.string(from: Date())

        let detailItem = NSMenuItem(title: currentStatus.detailMenuText(timestamp: timestamp), action: nil, keyEquivalent: "")
        detailItem.isEnabled = false
        statusDetailItem = detailItem
        menu.addItem(detailItem)
        menu.addItem(.separator())

        if interfaces.isEmpty {
            let emptyItem = NSMenuItem(title: "Interfaces: not yet set.", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for (index, interface) in interfaces.enumerated() {
                let item = NSMenuItem(title: interface.name, action: #selector(wakeInterface(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = interface

                if let shortcut = ShortcutMapper.shortcut(for: index) {
                    item.keyEquivalent = shortcut.keyEquivalent
                    item.keyEquivalentModifierMask = shortcut.modifiers
                }
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let loginItemsItem = NSMenuItem(title: "Launch at Login...", action: #selector(openLoginItemsSettings), keyEquivalent: "")
        loginItemsItem.target = self
        menu.addItem(loginItemsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)

        statusItem.menu = menu
        applyStatus(currentStatus)
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindow(settingsManager: settingsManager) {
                NotificationCenter.default.post(name: NSNotification.Name("SettingsChanged"), object: nil)
            }
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openLoginItemsSettings() {
        if let modern = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"),
           NSWorkspace.shared.open(modern) {
            return
        }

        if let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.users?LoginItems") {
            _ = NSWorkspace.shared.open(fallback)
        }
    }

    @objc private func wakeInterface(_ sender: NSMenuItem) {
        guard let interface = sender.representedObject as? Interface else { return }

        wakeSender.sendWakePacket(to: interface.mac) { [weak self] result in
            Task { @MainActor [weak self] in
                switch result {
                case .success:
                    self?.applyStatus(.success("\(interface.name): Sent"))
                case .failure(let error):
                    let detail = error.localizedDescription
                    self?.applyStatus(.failure("\(interface.name): \(detail)"))
                }
            }
        }
    }

    private func applyStatus(_ status: MenuStatus) {
        currentStatus = status
        guard let button = statusItem.button else { return }

        let baseImage = NSImage(systemSymbolName: Self.statusSymbolName, accessibilityDescription: "Wake on LAN")
        let whiteConfig = NSImage.SymbolConfiguration(hierarchicalColor: .white)
        let whiteImage = baseImage?.withSymbolConfiguration(whiteConfig) ?? baseImage
        whiteImage?.isTemplate = false

        button.image = whiteImage
        button.contentTintColor = nil
        button.title = ""
        button.imagePosition = .imageOnly
        let timestamp = timestampFormatter.string(from: Date())
        statusDetailItem?.title = status.detailMenuText(timestamp: timestamp)
    }
}
