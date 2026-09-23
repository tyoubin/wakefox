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
    private struct StatusIconOption {
        let symbolName: String
        let title: String
    }

    private static let statusIconPreferenceKey = "menuBarIconSymbolName"
    private static let statusIconOptions = [
        StatusIconOption(symbolName: "network", title: "Network"),
        StatusIconOption(symbolName: "wifi", title: "Wi-Fi"),
        StatusIconOption(symbolName: "bolt.horizontal.circle", title: "Wake / Power"),
        StatusIconOption(symbolName: "antenna.radiowaves.left.and.right", title: "Broadcast"),
        StatusIconOption(symbolName: "desktopcomputer", title: "Computer"),
        StatusIconOption(symbolName: "power", title: "Power")
    ]

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
                guard let self else { return }
                DispatchQueue.main.async {
                    self.constructMenu()
                }
            }
        }
    }

    private func constructMenu() {
        let menu = statusItem.menu ?? NSMenu()
        menu.removeAllItems()
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

        menu.addItem(makeStatusIconMenuItem())

        let loginItemsItem = NSMenuItem(title: "Launch at Login...", action: #selector(openLoginItemsSettings), keyEquivalent: "")
        loginItemsItem.target = self
        menu.addItem(loginItemsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)

        if statusItem.menu !== menu {
            statusItem.menu = menu
        }
        applyStatus(currentStatus)
    }

    private func makeStatusIconMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Menu Bar Icon", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let selectedSymbolName = selectedStatusSymbolName

        for option in Self.statusIconOptions {
            let optionItem = NSMenuItem(title: option.title,
                                        action: #selector(selectStatusIcon(_:)),
                                        keyEquivalent: "")
            optionItem.target = self
            optionItem.representedObject = option.symbolName
            optionItem.state = option.symbolName == selectedSymbolName ? .on : .off
            optionItem.image = NSImage(systemSymbolName: option.symbolName,
                                       accessibilityDescription: option.title)
            submenu.addItem(optionItem)
        }

        item.submenu = submenu
        return item
    }

    private var selectedStatusSymbolName: String {
        let storedName = UserDefaults.standard.string(forKey: Self.statusIconPreferenceKey)
        return Self.statusIconOptions.contains { $0.symbolName == storedName }
            ? storedName!
            : Self.statusIconOptions[0].symbolName
    }

    @objc private func selectStatusIcon(_ sender: NSMenuItem) {
        guard let symbolName = sender.representedObject as? String,
              Self.statusIconOptions.contains(where: { $0.symbolName == symbolName }) else {
            return
        }

        UserDefaults.standard.set(symbolName, forKey: Self.statusIconPreferenceKey)
        constructMenu()
    }

    @objc private func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
        } else {
            let window = SettingsWindow(settingsManager: settingsManager) {
                NotificationCenter.default.post(name: NSNotification.Name("SettingsChanged"), object: nil)
            }
            settingsWindow = window
            window.isReleasedWhenClosed = false
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self, weak window] _ in
                Task { @MainActor [weak self, weak window] in
                    guard let self, let window, self.settingsWindow === window else { return }
                    self.settingsWindow = nil
                }
            }
            window.makeKeyAndOrderFront(nil)
        }
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

        let baseImage = NSImage(systemSymbolName: selectedStatusSymbolName, accessibilityDescription: "Wake on LAN")
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
